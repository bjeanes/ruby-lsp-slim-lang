# frozen_string_literal: true

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

      class << self
        def extract(source)
          new.extract(source)
        end
      end

      def extract(source)
        @spans = []
        @interpolatable = []
        call(source)
        render(source)
      end

      protected

      def parse_line_indicators
        # Since Slim interpolates inline HTML (`<b>#{x}</b>`) the same way as text, the rest of the line is recorded for
        # `interpolations` to search.
        @interpolatable << Span.new(@lineno, column, @lineno, @orig_line.size) if @line.start_with?("<")
        return super unless @line =~ @embedded_re && Regexp.last_match(1) == "ruby"

        header_line = @lineno
        super
        @spans << Span.new(header_line + 1, 0, @lineno, @orig_line.size) if @lineno > header_line
      end

      def parse_broken_line
        start_line = @lineno
        start_column = column + @line[/\A\s*/].size
        code = super
        @spans << Span.new(start_line, start_column, @lineno, @orig_line.rstrip.size)
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
        @interpolatable << Span.new(start_line, start_column, @lineno, @orig_line.size)
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

        lines.each_with_index.map do |line, index|
          line.each_char.with_index.map do |char, col|
            case ruby[index][col]
            when true then char
            when :separator then ";"
            else " "
            end
          end.join
        end.join("\n")
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
