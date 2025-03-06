# frozen_string_literal: true

Gem::Specification.new do |s|
  s.name = "ruby-lsp"
  s.version = File.read("VERSION").strip
  s.authors = ["Shopify"]
  s.email = ["ruby@shopify.com"]
  s.metadata["allowed_push_host"] = "https://rubygems.org"
  s.metadata["documentation_uri"] = "https://shopify.github.io/ruby-lsp/"

  s.summary = "An opinionated language server for Ruby"
  s.description = "An opinionated language server for Ruby"
  s.homepage = "https://github.com/Shopify/ruby-lsp"
  s.license = "MIT"

  s.files = Dir.glob("lib/**/*.rb") + ["README.md", "VERSION", "LICENSE.txt"] + Dir.glob("static_docs/**/*.md")
  s.bindir = "exe"
  s.executables = ["ruby-lsp", "ruby-lsp-check", "ruby-lsp-launcher", "ruby-lsp-test-exec"]
  s.require_paths = ["lib"]

  # Dependencies must be kept in sync with the checks in the extension side on workspace.ts
  s.add_dependency("json_rpc_handler", "~> 0.1.1")
  s.add_dependency("language_server-protocol", "~> 3.17.0")
  s.add_dependency("prism", ">= 1.2", "< 2.0")
  s.add_dependency("rbs", ">= 3", "< 5")
  s.add_dependency("sorbet-runtime", ">= 0.5.10782")
  s.add_dependency("webrick", ">= 1.8")

  s.required_ruby_version = ">= 3.0"
end
