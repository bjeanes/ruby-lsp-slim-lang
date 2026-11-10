# frozen_string_literal: true

require "ruby_lsp/addon"
require "ruby_lsp/slim_lang/slim_document"
require "ruby_lsp/slim_lang/version"

module RubyLsp
  module SlimLang
    class Addon < ::RubyLsp::Addon
      def activate(global_state, outgoing_queue)
        Store.prepend(StorePatch) unless Store <= StorePatch
      end

      def deactivate; end

      def name
        "Ruby LSP Slim Lang"
      end

      def version
        VERSION
      end
    end

    # Ruby LSP picks a document class from a fixed list of language IDs. Add-ons have no way to register another. Since
    # the server maps unknown language IDs, including `slim`, to Ruby, this picks `SlimDocument` by file extension.
    module StorePatch
      def set(uri:, source:, version:, language_id:)
        return super unless File.extname(uri.path.to_s) == ".slim"

        @state[uri.to_s] = SlimDocument.new(source: source, version: version, uri: uri, global_state: @global_state)
      end
    end
  end
end
