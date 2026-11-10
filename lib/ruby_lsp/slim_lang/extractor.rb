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
        call(source)
        render(source)
      end

      protected

      def parse_line_indicators
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

      private

      def column
        @orig_line.size - @line.size
      end

      # Marks which characters of each line belong to Ruby, then blanks the rest.
      def render(source)
        lines = source.split("\n", -1)
        ruby = lines.map { |line| Array.new(line.size, false) }

        @spans.each do |span|
          (span.start_line..span.end_line).each do |lineno|
            from = lineno == span.start_line ? span.start_column : 0
            to = lineno == span.end_line ? span.end_column : lines[lineno - 1].size
            ruby[lineno - 1].fill(true, from...to)
          end
        end

        lines.each_with_index.map do |line, index|
          line.each_char.with_index.map { |char, col| ruby[index][col] ? char : " " }.join
        end.join("\n")
      end
    end
  end
end
