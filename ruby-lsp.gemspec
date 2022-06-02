# frozen_string_literal: true

Gem::Specification.new do |s|
  s.name = "ruby-lsp"
  s.version = File.read("VERSION").strip
  s.authors = ["Shopify"]
  s.email = ["ruby@shopify.com"]
  s.metadata["allowed_push_host"] = "https://rubygems.org"

  s.summary = "A simple language server for ruby"
  s.description = "A simple language server for ruby"
  s.homepage = "https://github.com/Shopify/ruby-lsp"
  s.license = "MIT"

  s.files = Dir.chdir(File.expand_path(__dir__)) do
    %x(git ls-files -z).split("\x0").reject { |f| f.match(%r{\A(?:test|spec|features)/}) }
  end
  s.bindir = "exe"
  s.executables = s.files.grep(/\Aexe/) { |f| File.basename(f) }
  s.require_paths = ["lib"]

  s.add_dependency("language_server-protocol")
  s.add_dependency("rubocop", ">= 1.0")
  s.add_dependency("sorbet-runtime")
  s.add_dependency("syntax_tree", ">= 2.3")
end
