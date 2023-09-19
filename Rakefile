# frozen_string_literal: true

require "bundler/gem_tasks"
require "rake/testtask"
require "rdoc/task"
require "ruby_lsp/check_docs"

Rake::TestTask.new(:test) do |t|
  t.libs << "test"
  t.libs << "lib"
  t.test_files = FileList["test/**/*_test.rb", "lib/ruby_indexer/test/**/*_test.rb"].exclude("test/fixtures/yarp/**/*")
end

RDoc::Task.new do |rdoc|
  rdoc.main = "README.md"
  rdoc.title = "Ruby LSP documentation"
  rdoc.rdoc_files.include("*.md", "lib/**/*.rb")
  rdoc.rdoc_dir = "docs"
  rdoc.markup = "markdown"
  rdoc.options.push("--copy-files", "misc")
  rdoc.options.push("--copy-files", "LICENSE.txt")
end

require "rubocop/rake_task"

RuboCop::RakeTask.new

RubyLsp::CheckDocs.new(FileList["#{__dir__}/lib/ruby_lsp/**/*.rb"], FileList["#{__dir__}/misc/**/*.gif"])

task default: [:test]
