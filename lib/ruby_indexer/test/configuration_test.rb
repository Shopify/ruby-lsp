# typed: true
# frozen_string_literal: true

require "test_helper"

module RubyIndexer
  class ConfigurationTest < Minitest::Test
    def setup
      @config = Configuration.new
    end

    def test_load_configuration_executes_configure_block
      @config.load_config
      indexables = @config.indexables

      assert(indexables.none? { |indexable| indexable.full_path.include?("test/fixtures") })
      assert(indexables.none? { |indexable| indexable.full_path.include?("minitest-reporters") })
      assert(indexables.none? { |indexable| indexable.full_path.include?("ansi") })
      assert(indexables.any? { |indexable| indexable.full_path.include?("sorbet-runtime") })
      assert(indexables.none? { |indexable| indexable.full_path == __FILE__ })
    end

    def test_indexables_only_includes_gem_require_paths
      @config.load_config
      indexables = @config.indexables

      Bundler.locked_gems.specs.each do |lazy_spec|
        next if lazy_spec.name == "ruby-lsp"

        spec = Gem::Specification.find_by_name(lazy_spec.name)
        assert(indexables.none? { |indexable| indexable.full_path.start_with?("#{spec.full_gem_path}/test/") })
      rescue Gem::MissingSpecError
        # Transitive dependencies might be missing when running tests on Windows
      end
    end

    def test_indexables_does_not_include_default_gem_path_when_in_bundle
      @config.load_config
      indexables = @config.indexables

      assert(
        indexables.none? { |indexable| indexable.full_path.start_with?("#{RbConfig::CONFIG["rubylibdir"]}/psych") },
      )
    end

    def test_indexables_includes_default_gems
      @config.load_config
      indexables = @config.indexables.map(&:full_path)

      assert_includes(indexables, "#{RbConfig::CONFIG["rubylibdir"]}/pathname.rb")
      assert_includes(indexables, "#{RbConfig::CONFIG["rubylibdir"]}/ipaddr.rb")
      assert_includes(indexables, "#{RbConfig::CONFIG["rubylibdir"]}/abbrev.rb")
    end

    def test_indexables_includes_project_files
      @config.load_config
      indexables = @config.indexables.map(&:full_path)

      Dir.glob("#{Dir.pwd}/lib/**/*.rb").each do |path|
        next if path.end_with?("_test.rb")

        assert_includes(indexables, path)
      end
    end

    def test_indexables_avoids_duplicates_if_bundle_path_is_inside_project
      Bundler.settings.set_global("path", "vendor/bundle")
      config = Configuration.new
      config.load_config

      assert_includes(config.instance_variable_get(:@excluded_patterns), "#{Dir.pwd}/vendor/bundle/**/*.rb")
    ensure
      Bundler.settings.set_global("path", nil)
    end

    def test_indexables_does_not_include_gems_own_installed_files
      @config.load_config
      indexables = @config.indexables

      assert(
        indexables.none? do |indexable|
          indexable.full_path.start_with?(Bundler.bundle_path.join("gems", "ruby-lsp").to_s)
        end,
      )
    end

    def test_indexables_does_not_include_non_ruby_files_inside_rubylibdir
      path = Pathname.new(RbConfig::CONFIG["rubylibdir"]).join("extra_file.txt").to_s
      FileUtils.touch(path)
      indexables = @config.indexables

      assert(indexables.none? { |indexable| indexable.full_path == path })
    ensure
      FileUtils.rm(T.must(path))
    end

    def test_paths_are_unique
      @config.load_config
      indexables = @config.indexables

      assert_equal(indexables.uniq.length, indexables.length)
    end

    def test_configuration_raises_for_unknown_keys
      Psych::Nodes::Document.any_instance.expects(:to_ruby).returns({ "unknown_config" => 123 })

      assert_raises(ArgumentError) do
        @config.load_config
      end
    end

    def test_magic_comments_regex
      regex = RubyIndexer.configuration.magic_comment_regex

      [
        "# frozen_string_literal:",
        "# typed:",
        "# compiled:",
        "# encoding:",
        "# shareable_constant_value:",
        "# warn_indent:",
        "# rubocop:",
        "# nodoc:",
        "# doc:",
        "# coding:",
        "# warn_past_scope:",
      ].each do |comment|
        assert_match(regex, comment)
      end
    end
  end
end
