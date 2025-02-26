# typed: true
# frozen_string_literal: true

require "test_helper"
require "yaml"

class CiConfigurationTest < Minitest::Test
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

  private

  def development_ruby_version_from_dot_ruby_version_file
    contents = File.read(".ruby-version").chomp
    flunk("Failed to read .ruby-version file") if contents.empty?

    major_and_minor_only = contents[/\d+\.\d+/]
    flunk("Failed to extract major and minor version from .ruby-version file") if major_and_minor_only.nil?

    major_and_minor_only
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
