# frozen_string_literal: true

require "ruby_lsp/slim_lang/extractor"

module RubyLsp
  module SlimLang
    class SlimDocument < ERBDocument
      # @override
      def parse!
        return false unless @needs_parsing

        @needs_parsing = false
        @ruby_source = extract_ruby
        @parse_result = Prism.parse_lex(@ruby_source, partial_script: true)
        @code_units_cache = @parse_result.code_units_cache(@encoding)
        true
      end

      # Since the extracted Ruby is longer than the template wherever an implicit `end` was appended, the editor's
      # positions have to be resolved against the extracted Ruby rather than the template.
      # @override
      def find_index_by_position(start_pos, end_pos = nil)
        scanner = ruby_source_scanner
        [scanner.find_char_position(start_pos), end_pos && scanner.find_char_position(end_pos)]
      end

      # Ruby LSP asks its VS Code extension to delegate requests on positions inside the host language. The extension
      # forwards them to its HTML provider whatever the file type. Since Slim markup isn't HTML, no position in a Slim
      # document counts as inside it.
      # @override
      def inside_host_language?(_char_position)
        false
      end

      private

      # Ruby LSP parses a document in its main loop, outside the `rescue` that turns a failing request into an error
      # response. An exception here would stop the server.
      def extract_ruby
        Extractor.extract(@source, encoding: @encoding)
      rescue StandardError
        "\n" * @source.count("\n")
      end

      def ruby_source_scanner
        case @encoding
        when Encoding::UTF_8 then Utf8Scanner.new(@ruby_source)
        when Encoding::UTF_16LE then Utf16Scanner.new(@ruby_source)
        else Utf32Scanner.new(@ruby_source)
        end
      end
    end
  end
end
