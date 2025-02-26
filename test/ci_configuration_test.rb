# typed: true
# frozen_string_literal: true

require "test_helper"
require "yaml"

class CiConfigurationTest < Minitest::Test
  # As the VSCode extension activation script runs before we've checked the user's Ruby version
  # (its purpose is to get that version so we can check it for compatibility), we need to test
  # that the activation script works with the oldest Ruby version the user might have installed,
  # regardless of if the current project is a Ruby project at all.
  #
  # 2.0 is the oldest Ruby version supported by RuboCop's TargetRubyVersion config, so we use that.
  VSCODE_EXTENSION_ACTIVATION_RUBY_VERSION = "2.0"

  def test_matrix_includes_minimum_ruby_version
    minimum_ruby_version = minimum_ruby_version_from_gemspec

    each_ci_matrix_ruby_entry do |matrix_ruby_versions, path|
      assert_includes(
        matrix_ruby_versions,
        minimum_ruby_version,
        "CI matrix #{path.join(".")} does not include minimum required ruby version #{minimum_ruby_version}",
      )
    end
  end

  def test_matrix_includes_development_ruby_version
    development_ruby_version = development_ruby_version_from_dot_ruby_version_file

    each_ci_matrix_ruby_entry do |matrix_ruby_versions, path|
      assert_includes(
        matrix_ruby_versions,
        development_ruby_version,
        "CI matrix #{path.join(".")} does not include development ruby version #{development_ruby_version}",
      )
    end
  end

  def test_vscode_rubocop_config_targets_ancient_ruby_version
    assert_equal(
      target_ruby_version_from_vscode_rubocop_yml,
      VSCODE_EXTENSION_ACTIVATION_RUBY_VERSION,
      "VSCode rubocop config must target ruby version #{VSCODE_EXTENSION_ACTIVATION_RUBY_VERSION} to ensure activation works regardless of user's Ruby version",
    )
  end

  private

  def minimum_ruby_version_from_gemspec
    minimum_ruby_version = File.read("ruby-lsp.gemspec")[/(?<=required_ruby_version = ">= ).*(?="$)/]

    return minimum_ruby_version unless minimum_ruby_version.nil?

    flunk("Failed to extract required_ruby_version from gemspec")
  end

  def development_ruby_version_from_dot_ruby_version_file
    contents = File.read(".ruby-version").chomp
    flunk("Failed to read .ruby-version file") if contents.empty?

    major_and_minor_only = contents[/\d+\.\d+/]
    flunk("Failed to extract major and minor version from .ruby-version file") if major_and_minor_only.nil?

    major_and_minor_only
  end

  def target_ruby_version_from_vscode_rubocop_yml
    version = YAML.load_file("vscode/.rubocop.yml").dig("AllCops", "TargetRubyVersion")
    flunk("Failed to extract target ruby version from vscode/.rubocop.yml file") if version.nil?

    version.to_s
  end

  def each_ci_matrix_ruby_entry(&block)
    each_ci_matrix_entry do |matrix, path|
      matrix_ruby_versions = matrix["ruby"]
      next if matrix_ruby_versions.nil?

      yield(matrix_ruby_versions, path)
    end
  end

  def each_ci_matrix_entry(hash = read_ci_workflow, path: [], &block)
    case hash
    when Hash
      hash.each do |key, value|
        if key == "matrix"
          yield(value, path)
        else
          each_ci_matrix_entry(value, path: path + [key], &block)
        end
      end
    when Array
      hash.each_with_index { |value, index| each_ci_matrix_entry(value, path: path + [index], &block) }
    end
  end

  def read_ci_workflow
    YAML.load_file(".github/workflows/ci.yml")
  end
end
