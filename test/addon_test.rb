# frozen_string_literal: true

require "test_helper"
require "minitest/mock"
require "tmpdir"
require "ruby_lsp/internal"
require "ruby_lsp/test_helper"
require "ruby_lsp/slim_lang/slim_document"

module RubyLsp
  module SlimLang
    class AddonTest < Minitest::Test
      include RubyLsp::TestHelper

      HELPERS_URI = URI("file:///fake/app/helpers.rb")
      HELPERS = <<~'RUBY'
        class Greeter
          def salute(name = nil) = "Hello #{name}"
        end

        module ApplicationHelper
          def profile_path(user) = "/users/#{user.id}"
        end
      RUBY

      TEMPLATE = <<~SLIM
        - greeter = Greeter.new
        - users.each do |user|
          a href=profile_path(user) = greeter.salute(user.name)
        p = Greeter
      SLIM

      def test_is_discovered_by_ruby_lsp
        with_slim("") do
          assert_includes(RubyLsp::Addon.addons.map(&:name), "Ruby LSP Slim Lang")
        end
      end

      def test_opens_slim_files_as_slim_documents
        with_slim(TEMPLATE) do |server, uri|
          assert_instance_of(SlimDocument, server.instance_variable_get(:@store).get(uri))

          server.process_message(open_message(URI("file:///fake/app/models/user.rb"), "class User; end", "ruby"))
          assert_instance_of(RubyDocument, server.instance_variable_get(:@store).get(URI("file:///fake/app/models/user.rb")))
        end
      end

      def test_definition_of_a_helper_in_an_attribute
        with_slim(TEMPLATE) do |server, uri|
          assert_equal([[HELPERS_URI.to_s, 5]], definitions(server, uri, line: 2, character: 12))
        end
      end

      def test_definition_of_a_method_after_another_fragment_on_the_line
        with_slim(TEMPLATE) do |server, uri|
          assert_equal([[HELPERS_URI.to_s, 1]], definitions(server, uri, line: 2, character: 40))
        end
      end

      def test_definition_below_an_implicit_end
        with_slim(TEMPLATE) do |server, uri|
          assert_equal([[HELPERS_URI.to_s, 0]], definitions(server, uri, line: 3, character: 5))
        end
      end

      def test_hover_on_a_constant
        with_slim(TEMPLATE) do |server, uri|
          server.process_message(request("textDocument/hover", uri, line: 0, character: 14))

          assert_match("Greeter", pop_result(server).response.contents.value)
        end
      end

      def test_completion_on_a_known_receiver
        with_slim("p = Greeter.new.sa\n") do |server, uri|
          server.process_message(request("textDocument/completion", uri, line: 0, character: 18))

          assert_includes(pop_result(server).response.map(&:label), "salute")
        end
      end

      def test_definition_in_a_template_that_is_not_open
        Dir.mktmpdir do |dir|
          path = File.join(dir, "show.slim")
          File.write(path, "p café\n= Greeter\n")
          uri = URI::Generic.from_path(path: path)

          with_slim("") do |server|
            server.instance_variable_get(:@store).get(uri).parse!

            assert_equal([[HELPERS_URI.to_s, 0]], definitions(server, uri, line: 1, character: 3))
          end
        end
      end

      def test_parse_never_raises
        Extractor.stub(:extract, ->(*) { raise "unexpected" }) do
          document = SlimDocument.new(
            source: "p = x\n", version: 1, uri: URI("file:///fake/a.slim"), global_state: GlobalState.new,
          )

          assert_equal("\n", document.parse_result.source.source)
        end
      end

      private

      def with_slim(template)
        uri = URI("file:///fake/app/views/users/index.html.slim")

        with_server do |server|
          server.global_state.index.index_single(HELPERS_URI, HELPERS)
          server.process_message(open_message(uri, template, "slim"))
          yield server, uri
        end
      end

      def open_message(uri, text, language_id)
        {
          method: "textDocument/didOpen",
          params: { textDocument: { uri: uri, text: text, version: 1, languageId: language_id } },
        }
      end

      def request(method, uri, line:, character:)
        { id: 1, method: method, params: { textDocument: { uri: uri }, position: { line: line, character: character } } }
      end

      def definitions(server, uri, line:, character:)
        server.process_message(request("textDocument/definition", uri, line: line, character: character))
        pop_result(server).response.map { |link| [link.target_uri, link.target_range.start.line] }
      end
    end
  end
end
