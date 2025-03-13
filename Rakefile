# frozen_string_literal: true

require "bundler/gem_tasks"
require "rake/testtask"

Rake::TestTask.new(:test) do |t|
  t.libs << "test"
  t.libs << "lib"
  t.test_files = FileList["test/**/*_test.rb"].exclude("test/fixtures/prism/**/*")
end

namespace :test do
  Rake::TestTask.new(:indexer) do |t|
    t.libs << "test"
    t.libs << "lib"
    t.test_files = FileList["lib/ruby_indexer/test/**/*_test.rb"]
  end
end

require "rubocop/rake_task"

RuboCop::RakeTask.new

task default: [:test, "test:indexer"]
