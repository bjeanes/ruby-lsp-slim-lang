# frozen_string_literal: true

require "prism"
require "slim"

module RubyLsp
  module SlimLang
    # Builds a copy of a Slim template where everything but the Ruby is blanked, so that the Ruby keeps the line and
    # column it has in the template.
    #
    # The hooks below read the parser's position as it consumes each Ruby fragment. They override protected methods,
    # which are outside Slim's public API. That is why the gemspec pins the `slim` major version.
    class Extractor < ::Slim::Parser
      Span = Struct.new(:start_line, :start_column, :end_line, :end_column)

      OPENS_BLOCK = ::Slim::EndInserter::IF_RE
      CONTINUES_BLOCK = /\A-\s*#{::Slim::EndInserter::ELSE_RE.source.delete_prefix("\\A")}/
      SLIM_COMMENT = %r{\A/(?![!\[])} # `/!` and `/[` are HTML comments
      MAX_SKIPPED_STATEMENTS = 10
      INTERPOLATED_ENGINES = ["javascript", "css", "markdown", "asciidoc", "textile", "rdoc"].freeze

      class << self
        def extract(source, encoding: Encoding::UTF_16LE)
          new.extract(source, encoding: encoding)
        end
      end

      def extract(source, encoding: Encoding::UTF_16LE)
        # Ruby LSP reads a template that isn't open in the editor as binary. Matching Slim's UTF-8 patterns against
        # non-ASCII bytes in it would raise, as would splitting it if it held invalid UTF-8.
        source = source.dup.force_encoding(Encoding::UTF_8).scrub
        # `Slim::Engine` strips a byte order mark before parsing, which calling the parser directly skips. A space in
        # its place keeps the first line's Ruby at the column it has in the template.
        without_bom = source.sub(/\A\uFEFF/, " ")
        @encoding = encoding
        skipped = {}
        tree = begin
          @spans = []
          @interpolatable = []
          @text_blocks = {}.compare_by_identity
          @open_blocks = []
          @ends = Hash.new(0)
          @last_content_line = 0
          call(without_lines(without_bom, skipped))
        rescue ::Slim::Parser::SyntaxError
          # Since Slim can raise far below where the problem is (an unclosed `a(href=x` raises at the end of the file),
          # we skip the line the failing statement started on, not the line Slim reports.
          #
          # Rather than blanking a skipped line, we first replace it with a `div`, so that the lines nested under it
          # still have a parent. If the `div` fails too (as it would if nested under an `img/`), we blank the line.
          if !skipped.key?(@statement_line) && skipped.size < MAX_SKIPPED_STATEMENTS
            skipped[@statement_line] = :placeholder
            retry
          elsif skipped[@statement_line] == :placeholder
            skipped[@statement_line] = :blank
            retry
          end
          @stacks.first
        end
        classify_text_blocks(tree)
        @open_blocks.each { @ends[@last_content_line] += 1 }
        render(source)
      end

      protected

      def next_line
        @last_content_line = @lineno if @orig_line&.match?(/\S/)
        super
      end

      def parse_line
        @statement_line = @lineno
        if @line.match?(/\S/)
          @indent = get_indent(@line)
          close_blocks(continuing: @line.lstrip.match?(CONTINUES_BLOCK)) unless @line.lstrip.match?(SLIM_COMMENT)
        end
        super
      end

      def parse_line_indicators
        # Since Slim interpolates inline HTML (`<b>#{x}</b>`) the same way as text, the rest of the line is recorded for
        # `interpolations` to search.
        @interpolatable << Span.new(@lineno, column, @lineno, @orig_line.size) if @line.start_with?("<")
        super
      end

      def parse_broken_line
        start_line = @lineno
        start_column = column + @line[/\A\s*/].size
        code = super
        @spans << Span.new(start_line, start_column, @lineno, @orig_line.rstrip.size)
        @open_blocks << @indent if code.match?(OPENS_BLOCK)
        code
      end

      def parse_ruby_code(outer_delimiter)
        start_line = @lineno
        start_column = column
        code = super
        @spans << Span.new(start_line, start_column, @lineno, column)
        code
      end

      def parse_text_block(first_line = nil, text_indent = nil)
        start_line = @lineno
        start_column = first_line ? @orig_line.size - first_line.size : @orig_line.size
        text = super
        @text_blocks[text] = Span.new(start_line, start_column, @lineno, @orig_line.size)
        text
      end

      def parse_quoted_attribute(quote)
        start_line = @lineno
        start_column = column
        value = super
        @interpolatable << Span.new(start_line, start_column, @lineno, column)
        value
      end

      private

      # Slim parses the body of a `ruby:` block as a text block, the same as plain text. We can only tell them apart by
      # where each one ends up in the parse tree, once Slim has finished parsing.
      def classify_text_blocks(tree)
        engines = {}.compare_by_identity
        each_embedded(tree) { |engine, body| engines[body] = engine }
        @text_blocks.each do |body, span|
          case engines[body]
          when "ruby" then @spans << span
          when nil, *INTERPOLATED_ENGINES then @interpolatable << span
          end
        end
      end

      def each_embedded(exp, &block)
        return unless exp.is_a?(Array)

        yield exp[2], exp[3] if exp[0] == :slim && exp[1] == :embedded
        exp.each { |child| each_embedded(child, &block) }
      end

      # Slim closes a block when a line is indented no deeper than the code that opened it. A `- else` (or `elsif`,
      # `when`, etc.) at the same depth continues the block instead. Here we pop it without adding an `end`. Since
      # `OPENS_BLOCK` also matches `else`, the `- else` line pushes the block again when its code is parsed.
      def close_blocks(continuing:)
        while (indent = @open_blocks.last) && indent >= @indent
          @open_blocks.pop
          break if continuing && indent == @indent

          @ends[@last_content_line] += 1
        end
      end

      # Without this, an emoji before some Ruby would shift that Ruby's column.
      def code_units(char)
        return 1 unless char.valid_encoding?

        case @encoding
        when Encoding::UTF_8 then char.bytesize
        when Encoding::UTF_16LE then char.ord > 0xFFFF ? 2 : 1
        else 1
        end
      end

      def without_lines(source, skipped)
        source.split("\n", -1).each_with_index.map do |line, index|
          case skipped[index + 1]
          when :placeholder then "#{line[/\A\s*/]}div"
          when :blank then ""
          else line
          end
        end.join("\n")
      end

      def column
        @orig_line.size - @line.size
      end

      # Marks which characters of each line belong to Ruby, then blanks the rest.
      def render(source)
        lines = source.split("\n", -1)
        ruby = lines.map { |line| Array.new(line.size, false) }
        spans = @spans + interpolations(lines)

        spans.each do |span|
          each_segment(span, lines) { |index, from, to| ruby[index].fill(true, from...to) }
        end

        # Without a separator, `a href=foo title=bar` would extract to `foo bar`, which Ruby reads as `foo(bar)`.
        spans.each do |span|
          line = ruby[span.end_line - 1]
          line[span.end_column] ||= :separator if span.end_column < line.size
        end

        rendered = lines.each_with_index.map do |line, index|
          line.each_char.with_index.map do |char, col|
            case ruby[index][col]
            when true then char
            when :separator then ";".ljust(code_units(char))
            else " " * code_units(char)
            end
          end.join
        end

        move_ends_off_heredoc_terminators(rendered)
        blank_comments_before_ends(rendered)
        rendered.each_with_index.map { |line, index| line + ";end" * @ends[index + 1] }.join("\n")
      end

      # Since a heredoc's closing line can hold nothing but its terminator, the `end`s for that line go on the next one.
      # When that line's indent is too narrow for them, they go after its Ruby, which puts that Ruby inside the block.
      # We accept the wrong semantics on that one line to keep the syntax valid. Giving the `end`s a line of their own
      # would put every line below it out of step with the template. On the terminator, they would leave the heredoc
      # open to the end of the file.
      def move_ends_off_heredoc_terminators(rendered)
        tokens = Prism.lex(rendered.join("\n"), partial_script: true).value
        tokens.each do |token, _state|
          next unless token.type == :HEREDOC_END && (count = @ends.delete(token.location.start_line))

          index = token.location.start_line
          following = rendered[index] ||= +""
          ends = "end;" * count
          if following.start_with?(" " * ends.size)
            rendered[index] = ends + following[ends.size..]
          else
            @ends[index + 1] += count
          end
        end
      end

      # Without this, `- foo # note` followed by a dedent would extract to `foo # note;end`, where the `end` is commented
      # out. Prism finds the comments, because a `#` inside a string (as in `"#{x} # y"`) isn't one.
      def blank_comments_before_ends(rendered)
        return if @ends.empty?

        Prism.parse_comments(rendered.join("\n"), partial_script: true).each do |comment|
          next unless comment.is_a?(Prism::InlineComment)

          index = comment.location.start_line - 1
          next unless @ends.key?(index + 1)

          line = rendered[index]
          start = line.byteslice(0, comment.location.start_column).size
          rendered[index] = line[0...start] + " " * (line.size - start)
        end
      end

      def interpolations(lines)
        @interpolatable.flat_map do |span|
          found = []
          each_segment(span, lines) do |index, from, to|
            line = lines[index]
            line[from...to].scan(/(?<!\\)#\{/) do
              code_start = from + Regexp.last_match.end(0)
              code_end = closing_brace(line, code_start, to)
              if line[code_start] == "{" && line[code_end - 1] == "}"
                code_start += 1
                code_end -= 1
              end
              found << Span.new(index + 1, code_start, index + 1, code_end)
            end
          end
          found
        end
      end

      def closing_brace(line, from, to)
        depth = 1
        (from...to).each do |col|
          depth += 1 if line[col] == "{"
          depth -= 1 if line[col] == "}"
          return col if depth.zero?
        end
        to
      end

      def each_segment(span, lines)
        (span.start_line..span.end_line).each do |lineno|
          from = lineno == span.start_line ? span.start_column : 0
          to = lineno == span.end_line ? span.end_column : lines[lineno - 1].size
          yield lineno - 1, from, to
        end
      end
    end
  end
end
