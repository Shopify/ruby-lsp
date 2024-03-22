# typed: true
# frozen_string_literal: true

require "test_helper"

module RubyLsp
  class ConfigurationTest < Minitest::Test
    def test_returns_empty_hash_when_no_configuration_files_exist
      FileUtils.mv(".ruby-lsp.yml", ".ruby-lsp.yml.tmp")
      workspace_uri = URI::Generic.build(scheme: "file", host: nil, path: "/path/to/workspace")

      result = RubyLsp::Configuration.new(workspace_uri).indexing

      assert_empty(result)
    ensure
      FileUtils.mv(".ruby-lsp.yml.tmp", ".ruby-lsp.yml")
    end

    def test_supports_depecated_index_configuration_file
      FileUtils.mv(".ruby-lsp.yml", ".ruby-lsp.yml.tmp")
      File.write(".index.yml", <<~YAML)
        excluded_patterns:
          - "**/test/fixtures/**/*.rb"
      YAML
      workspace_uri = URI::Generic.build(scheme: "file", host: nil, path: Dir.pwd)

      result = RubyLsp::Configuration.new(workspace_uri).indexing

      assert_equal({ "excluded_patterns" => ["**/test/fixtures/**/*.rb"] }, result)
    ensure
      FileUtils.mv(".ruby-lsp.yml.tmp", ".ruby-lsp.yml")
      FileUtils.rm_f(".index.yml")
    end

    def test_supports_newer_configuration
      workspace_uri = URI::Generic.build(scheme: "file", host: nil, path: Dir.pwd)

      result = RubyLsp::Configuration.new(workspace_uri).indexing

      assert_equal({ "excluded_patterns" => ["**/test/fixtures/**/*.rb"] }, result)
    end

    def test_raises_if_indexing_key_is_missing
      FileUtils.mv(".ruby-lsp.yml", ".ruby-lsp.yml.tmp")
      File.write(".ruby-lsp.yml", <<~YAML)
        excluded_patterns:
          - "**/test/fixtures/**/*.rb"
      YAML
      workspace_uri = URI::Generic.build(scheme: "file", host: nil, path: Dir.pwd)

      error = assert_raises do
        RubyLsp::Configuration.new(workspace_uri).indexing
      end
      assert_equal("key not found: \"indexing\"", error.message)
      assert_instance_of(KeyError, error)
    ensure
      FileUtils.mv(".ruby-lsp.yml.tmp", ".ruby-lsp.yml")
    end
  end
end
