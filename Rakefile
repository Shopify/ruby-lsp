# frozen_string_literal: true

require "bundler/gem_tasks"
require "rake/testtask"
Dir["tasks/**/*.rake"].each { |t| load t }

Rake::TestTask.new(:test) do |t|
  t.libs << "test"
  t.libs << "lib"
  t.test_files = FileList["test/**/*_test.rb"]
end

require "rubocop/rake_task"

RuboCop::RakeTask.new

task default: [:test]
