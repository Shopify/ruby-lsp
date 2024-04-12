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

  s.files = Dir.glob("lib/**/*.rb") + ["README.md", "VERSION", "LICENSE.txt"]
  s.bindir = "exe"
  s.executables = ["ruby-lsp", "ruby-lsp-check", "ruby-lsp-doctor"]
  s.require_paths = ["lib"]

  s.add_dependency("language_server-protocol", "~> 3.17.0")
  s.add_dependency("prism", ">= 0.23.0", "< 0.25")
  s.add_dependency("sorbet-runtime", ">= 0.5.10782")

  s.required_ruby_version = ">= 3.0"
end
