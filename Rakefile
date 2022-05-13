# frozen_string_literal: true

require "bundler/gem_tasks"
require "rake/testtask"
require "yard"

Rake::TestTask.new(:test) do |t|
  t.libs << "test"
  t.libs << "lib"
  t.test_files = FileList["test/**/*_test.rb"]
end

YARD::Rake::YardocTask.new do |t|
  t.options = ["--markup", "markdown", "--output-dir", "docs"]
end

require "rubocop/rake_task"

RuboCop::RakeTask.new

task default: [:test]
