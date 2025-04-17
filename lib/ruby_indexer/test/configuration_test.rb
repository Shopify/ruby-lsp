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
      @config.apply_config({ "excluded_patterns" => ["**/fixtures/**/*"] })
      uris = @config.indexable_uris

      bundle_path = Bundler.bundle_path.join("gems")

      assert(uris.none? { |uri| uri.full_path.include?("test/fixtures") })
      assert(uris.none? { |uri| uri.full_path.include?(bundle_path.join("minitest-reporters").to_s) })
      assert(uris.none? { |uri| uri.full_path.include?(bundle_path.join("ansi").to_s) })
      assert(uris.any? { |uri| uri.full_path.include?(bundle_path.join("sorbet-runtime").to_s) })
      assert(uris.none? { |uri| uri.full_path == __FILE__ })
    end

    def test_indexable_uris_have_expanded_full_paths
      @config.apply_config({ "included_patterns" => ["**/*.rb"] })
      uris = @config.indexable_uris

      # All paths should be expanded
      assert(uris.all? { |uri| File.absolute_path?(uri.full_path) })
    end

    def test_indexable_uris_only_includes_gem_require_paths
      uris = @config.indexable_uris

      Bundler.locked_gems.specs.each do |lazy_spec|
        next if lazy_spec.name == "ruby-lsp"

        spec = Gem::Specification.find_by_name(lazy_spec.name)

        test_uris = uris.select do |uri|
          File.fnmatch?(File.join(spec.full_gem_path, "test/**/*"), uri.full_path, File::Constants::FNM_PATHNAME)
        end
        assert_empty(test_uris)
      rescue Gem::MissingSpecError
        # Transitive dependencies might be missing when running tests on Windows
      end
    end

    def test_indexable_uris_does_not_include_default_gem_path_when_in_bundle
      uris = @config.indexable_uris
      assert(uris.none? { |uri| uri.full_path.start_with?("#{RbConfig::CONFIG["rubylibdir"]}/psych") })
    end

    def test_indexable_uris_includes_default_gems
      paths = @config.indexable_uris.map(&:full_path)

      assert_includes(paths, "#{RbConfig::CONFIG["rubylibdir"]}/pathname.rb")
      assert_includes(paths, "#{RbConfig::CONFIG["rubylibdir"]}/ipaddr.rb")
      assert_includes(paths, "#{RbConfig::CONFIG["rubylibdir"]}/erb.rb")
    end

    def test_indexable_uris_includes_project_files
      paths = @config.indexable_uris.map(&:full_path)

      Dir.glob("#{Dir.pwd}/lib/**/*.rb").each do |path|
        next if path.end_with?("_test.rb")

        assert_includes(paths, path)
      end
    end

    def test_indexable_uris_avoids_duplicates_if_bundle_path_is_inside_project
      Bundler.settings.temporary(path: "vendor/bundle") do
        config = Configuration.new

        assert_includes(config.instance_variable_get(:@excluded_patterns), "vendor/bundle/**/*.rb")
      end
    end

    def test_indexable_uris_does_not_include_gems_own_installed_files
      uris = @config.indexable_uris
      uris_inside_bundled_lsp = uris.select do |uri|
        uri.full_path.start_with?(Bundler.bundle_path.join("gems", "ruby-lsp").to_s)
      end

      assert_empty(
        uris_inside_bundled_lsp,
        "Indexable URIs should not include files from the gem currently being worked on. " \
          "Included: #{uris_inside_bundled_lsp.map(&:full_path)}",
      )
    end

    def test_indexable_uris_does_not_include_non_ruby_files_inside_rubylibdir
      path = Pathname.new(RbConfig::CONFIG["rubylibdir"]).join("extra_file.txt").to_s
      FileUtils.touch(path)

      begin
        uris = @config.indexable_uris
        assert(uris.none? { |uri| uri.full_path == path })
      ensure
        FileUtils.rm(path)
      end
    end

    def test_paths_are_unique
      uris = @config.indexable_uris
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

    def test_indexable_uris_respect_given_workspace_path
      Dir.mktmpdir do |dir|
        FileUtils.mkdir(File.join(dir, "ignore"))
        FileUtils.touch(File.join(dir, "ignore", "file0.rb"))
        FileUtils.touch(File.join(dir, "file1.rb"))
        FileUtils.touch(File.join(dir, "file2.rb"))

        @config.apply_config({ "excluded_patterns" => ["ignore/**/*.rb"] })
        @config.workspace_path = dir

        uris = @config.indexable_uris
        assert(uris.none? { |uri| uri.full_path.start_with?(File.join(dir, "ignore")) })

        # The regular default gem path is ~/.rubies/3.4.1/lib/ruby/3.4.0
        # The alternative default gem path is ~/.rubies/3.4.1/lib/ruby/gems/3.4.0
        # Here part_1 contains ~/.rubies/3.4.1/lib/ruby/ and part_2 contains 3.4.0, so that we can turn it into the
        # alternative path
        part_1, part_2 = Pathname.new(RbConfig::CONFIG["rubylibdir"]).split
        other_default_gem_dir = part_1.join("gems").join(part_2).to_s

        # After switching the workspace path, all indexable URIs will be found in one of these places:
        # - The new workspace path
        # - The Ruby LSP's own code (because Bundler is requiring the dependency from source)
        # - Bundled gems
        # - Default gems
        # - Other default gem directory
        assert(
          uris.all? do |u|
            u.full_path.start_with?(dir) ||
            u.full_path.start_with?(File.join(Dir.pwd, "lib")) ||
            u.full_path.start_with?(Bundler.bundle_path.to_s) ||
            u.full_path.start_with?(RbConfig::CONFIG["rubylibdir"]) ||
            u.full_path.start_with?(other_default_gem_dir)
          end,
        )
      end
    end

    def test_includes_top_level_files
      Dir.mktmpdir do |dir|
        FileUtils.touch(File.join(dir, "find_me.rb"))
        @config.workspace_path = dir

        uris = @config.indexable_uris
        assert(uris.find { |u| File.basename(u.full_path) == "find_me.rb" })
      end
    end

    def test_transitive_dependencies_for_non_dev_gems_are_not_excluded
      Dir.mktmpdir do |dir|
        Dir.chdir(dir) do
          # Both IRB and debug depend on reline. Since IRB is in the default group, reline should not be excluded
          File.write(File.join(dir, "Gemfile"), <<~RUBY)
            source "https://rubygems.org"
            gem "irb"
            gem "ruby-lsp", path: "#{Bundler.root}"

            group :development do
              gem "debug"
            end
          RUBY

          Bundler.with_unbundled_env do
            capture_subprocess_io do
              system("bundle install")
            end

            stdout, _stderr = capture_subprocess_io do
              script = [
                "require \"ruby_lsp/internal\"",
                "print RubyIndexer::Configuration.new.instance_variable_get(:@excluded_gems).join(\",\")",
              ].join(";")
              system("bundle exec ruby -e '#{script}'")
            end

            excluded_gems = stdout.split(",")
            assert_includes(excluded_gems, "debug")
            refute_includes(excluded_gems, "reline")
            refute_includes(excluded_gems, "irb")
          end
        end
      end
    end

    def test_does_not_fail_if_there_are_missing_specs_due_to_platform_constraints
      Dir.mktmpdir do |dir|
        Dir.chdir(dir) do
          File.write(File.join(dir, "Gemfile"), <<~RUBY)
            source "https://rubygems.org"
            gem "ruby-lsp", path: "#{Bundler.root}"

            platforms :windows do
              gem "tzinfo"
              gem "tzinfo-data"
            end
          RUBY

          Bundler.with_unbundled_env do
            capture_subprocess_io { system("bundle install") }

            _stdout, stderr = capture_subprocess_io do
              script = [
                "require \"ruby_lsp/internal\"",
                "RubyIndexer::Configuration.new.indexable_uris",
              ].join(";")

              system("bundle exec ruby -e '#{script}'")
            end

            assert_empty(stderr)
          end
        end
      end
    end

    def test_indexables_include_non_test_files_in_test_directories
      # In order to linearize test parent classes and accurately detect the framework being used, then intermediate
      # parent classes _must_ also be indexed. Otherwise, we have no way of linearizing the rest of the ancestors to
      # determine what the test class ultimately inherits from.
      #
      # Therefore, we need to ensure that test files are excluded, but non test files inside test directories have to be
      # indexed
      FileUtils.touch("test/test_case.rb")

      uris = @config.indexable_uris
      project_paths = uris.filter_map do |uri|
        path = uri.full_path
        next if path.start_with?(Bundler.bundle_path.to_s) || path.start_with?(RbConfig::CONFIG["rubylibdir"])

        Pathname.new(path).relative_path_from(Dir.pwd).to_s
      end

      begin
        assert_includes(project_paths, "test/requests/support/expectations_test_runner.rb")
        assert_includes(project_paths, "test/test_helper.rb")
        assert_includes(project_paths, "test/test_case.rb")
      ensure
        FileUtils.rm("test/test_case.rb")
      end
    end
  end
end
