# typed: true
# frozen_string_literal: true

require "test_helper"
require "tmpdir"

class RuboCopRunnerTest < Minitest::Test
  def test_reuses_the_shared_project_index_when_enabled
    graph = Rubydex::Graph.new
    runner = RubyLsp::Requests::Support::RuboCopRunner.new(project_index: graph, workspace_path: Dir.pwd)
    config = ::RuboCop::Config.new("AllCops" => { "UseProjectIndex" => true })
    runner.instance_variable_set(:@config_for_working_directory, config)

    runner.send(:build_project_index, [])

    assert_same(graph, runner.instance_variable_get(:@project_index))
  end

  def test_does_not_use_the_shared_project_index_when_disabled
    graph = Rubydex::Graph.new
    runner = RubyLsp::Requests::Support::RuboCopRunner.new(project_index: graph, workspace_path: Dir.pwd)
    config = ::RuboCop::Config.new("AllCops" => {})
    runner.instance_variable_set(:@config_for_working_directory, config)

    runner.send(:build_project_index, [])

    refute_same(graph, runner.instance_variable_get(:@project_index))
  end

  def test_reuses_the_shared_project_index_when_the_workspace_path_is_a_symlink
    skip("Symlinks are unavailable on Windows") if Gem.win_platform?

    graph = Rubydex::Graph.new
    Dir.mktmpdir do |directory|
      workspace_path = File.join(directory, "workspace")
      File.symlink(Dir.pwd, workspace_path)

      runner = RubyLsp::Requests::Support::RuboCopRunner.new(project_index: graph, workspace_path: workspace_path)
      config = ::RuboCop::Config.new("AllCops" => { "UseProjectIndex" => true })
      runner.instance_variable_set(:@config_for_working_directory, config)

      runner.send(:build_project_index, [])

      assert_same(graph, runner.instance_variable_get(:@project_index))
    end
  end

  def test_does_not_reuse_the_shared_project_index_when_gem_sources_are_enabled
    graph = Rubydex::Graph.new
    runner = RubyLsp::Requests::Support::RuboCopRunner.new(project_index: graph, workspace_path: Dir.pwd)
    config = ::RuboCop::Config.new("AllCops" => {
      "UseProjectIndex" => true,
      "ProjectIndexIncludesGems" => true,
    })
    runner.instance_variable_set(:@config_for_working_directory, config)

    refute(runner.send(:shared_project_index_enabled?))
  end
end
