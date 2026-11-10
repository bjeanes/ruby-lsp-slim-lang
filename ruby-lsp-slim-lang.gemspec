# frozen_string_literal: true

require_relative "lib/ruby_lsp/slim_lang/version"

Gem::Specification.new do |spec|
  spec.name = "ruby-lsp-slim-lang"
  spec.version = RubyLsp::SlimLang::VERSION
  spec.authors = ["Bo Jeanes"]
  spec.email = ["bo@hivetechnologylabs.com"]

  spec.summary = "A Ruby LSP add-on for the Ruby code in Slim templates"
  spec.homepage = "https://github.com/bjeanes/ruby-lsp-slim-lang"
  spec.required_ruby_version = ">= 3.0"

  spec.files = Dir["lib/**/*.rb"]
  spec.require_paths = ["lib"]

  spec.add_dependency("ruby-lsp", ">= 0.26", "< 0.28")
  spec.add_dependency("slim", ">= 5.0", "< 6")
end
