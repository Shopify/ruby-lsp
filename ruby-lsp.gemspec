# frozen_string_literal: true

Gem::Specification.new do |s|
  s.name = "ruby-lsp"
  s.version = File.read("VERSION").strip
  s.authors = ["Shopify"]
  s.email = ["ruby@shopify.com"]
  s.metadata["allowed_push_host"] = "https://rubygems.org"

  s.summary = "An opinionated language server for Ruby"
  s.description = "An opinionated language server for Ruby"
  s.homepage = "https://github.com/Shopify/ruby-lsp"
  s.license = "MIT"

  s.files = Dir.glob("lib/**/*.rb") + ["README.md", "VERSION", "LICENSE.txt"]
  s.bindir = "exe"
  s.executables = ["ruby-lsp"]
  s.require_paths = ["lib"]

  s.add_dependency("language_server-protocol", "~> 3.17.0")
  s.add_dependency("sorbet-runtime")
  s.add_dependency("syntax_tree", ">= 4.0.0")

  s.required_ruby_version = ">= 2.7.3"
end
