# typed: true
# frozen_string_literal: true

require "test_helper"

module RubyIndexer
  class ConfigurationTest < Minitest::Test
    def setup
      @config = Configuration.new
      @workspace_path = File.expand_path(File.join("..", "..", ".."), __dir__)
      @config.workspace_path = @workspace_path
    end

    def test_load_configuration_executes_configure_block
      @config.apply_config({ "excluded_patterns" => ["**/fixtures/**/*.rb"] })
      uris = @config.indexables

      assert(uris.none? { |uri| uri.full_path.include?("test/fixtures") })
      assert(uris.none? { |uri| uri.full_path.include?("minitest-reporters") })
      assert(uris.none? { |uri| uri.full_path.include?("ansi") })
      assert(uris.any? { |uri| uri.full_path.include?("sorbet-runtime") })
      assert(uris.none? { |uri| uri.full_path == __FILE__ })
    end

    def test_indexables_have_expanded_full_paths
      @config.apply_config({ "included_patterns" => ["**/*.rb"] })
      uris = @config.indexables

      # All paths should be expanded
      assert(uris.all? { |uri| File.absolute_path?(uri.full_path) })
    end

    def test_indexables_only_includes_gem_require_paths
      uris = @config.indexables

      Bundler.locked_gems.specs.each do |lazy_spec|
        next if lazy_spec.name == "ruby-lsp"

        spec = Gem::Specification.find_by_name(lazy_spec.name)
        assert(uris.none? { |uri| uri.full_path.start_with?("#{spec.full_gem_path}/test/") })
      rescue Gem::MissingSpecError
        # Transitive dependencies might be missing when running tests on Windows
      end
    end

    def test_indexables_does_not_include_default_gem_path_when_in_bundle
      uris = @config.indexables
      assert(uris.none? { |uri| uri.full_path.start_with?("#{RbConfig::CONFIG["rubylibdir"]}/psych") })
    end

    def test_indexables_includes_default_gems
      paths = @config.indexables.map(&:full_path)

      assert_includes(paths, "#{RbConfig::CONFIG["rubylibdir"]}/pathname.rb")
      assert_includes(paths, "#{RbConfig::CONFIG["rubylibdir"]}/ipaddr.rb")
      assert_includes(paths, "#{RbConfig::CONFIG["rubylibdir"]}/erb.rb")
    end

    def test_indexables_includes_project_files
      paths = @config.indexables.map(&:full_path)

      Dir.glob("#{Dir.pwd}/lib/**/*.rb").each do |path|
        next if path.end_with?("_test.rb")

        assert_includes(paths, path)
      end
    end

    def test_indexables_avoids_duplicates_if_bundle_path_is_inside_project
      Bundler.settings.temporary(path: "vendor/bundle") do
        config = Configuration.new

        assert_includes(config.instance_variable_get(:@excluded_patterns), "vendor/bundle/**/*.rb")
      end
    end

    def test_indexables_does_not_include_gems_own_installed_files
      uris = @config.indexables
      indexables_inside_bundled_lsp = uris.select do |uri|
        uri.full_path.start_with?(Bundler.bundle_path.join("gems", "ruby-lsp").to_s)
      end

      assert_empty(
        indexables_inside_bundled_lsp,
        "Indexables should not include files from the gem currently being worked on. " \
          "Included: #{indexables_inside_bundled_lsp.map(&:full_path)}",
      )
    end

    def test_indexables_does_not_include_non_ruby_files_inside_rubylibdir
      path = Pathname.new(RbConfig::CONFIG["rubylibdir"]).join("extra_file.txt").to_s
      FileUtils.touch(path)

      uris = @config.indexables
      assert(uris.none? { |uri| uri.full_path == path })
    ensure
      FileUtils.rm(T.must(path))
    end

    def test_paths_are_unique
      uris = @config.indexables
      assert_equal(uris.uniq.length, uris.length)
    end

    def test_configuration_raises_for_unknown_keys
      assert_raises(ArgumentError) do
        @config.apply_config({ "unknown_config" => 123 })
      end
    end

    def test_magic_comments_regex
      regex = @config.magic_comment_regex

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

    def test_indexables_respect_given_workspace_path
      Dir.mktmpdir do |dir|
        FileUtils.mkdir(File.join(dir, "ignore"))
        FileUtils.touch(File.join(dir, "ignore", "file0.rb"))
        FileUtils.touch(File.join(dir, "file1.rb"))
        FileUtils.touch(File.join(dir, "file2.rb"))

        @config.apply_config({ "excluded_patterns" => ["ignore/**/*.rb"] })
        @config.workspace_path = dir

        uris = @config.indexables
        assert(uris.none? { |uri| uri.full_path.start_with?(File.join(dir, "ignore")) })

        # After switching the workspace path, all indexables will be found in one of these places:
        # - The new workspace path
        # - The Ruby LSP's own code (because Bundler is requiring the dependency from source)
        # - Bundled gems
        # - Default gems
        assert(
          uris.all? do |u|
            u.full_path.start_with?(dir) ||
            u.full_path.start_with?(File.join(Dir.pwd, "lib")) ||
            u.full_path.start_with?(Bundler.bundle_path.to_s) ||
            u.full_path.start_with?(RbConfig::CONFIG["rubylibdir"])
          end,
        )
      end
    end

    def test_includes_top_level_files
      Dir.mktmpdir do |dir|
        FileUtils.touch(File.join(dir, "find_me.rb"))
        @config.workspace_path = dir

        uris = @config.indexables
        assert(uris.find { |u| File.basename(u.full_path) == "find_me.rb" })
      end
    end
  end
end
