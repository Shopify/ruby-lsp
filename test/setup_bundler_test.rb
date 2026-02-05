# typed: true
# frozen_string_literal: true

require "test_helper"
require "ruby_lsp/setup_bundler"

class SetupBundlerTest < Minitest::Test
  # These tests run Bundler APIs in the same process as the main test process. This means that results can be memoized
  # from before these examples start running and they might get memoized for later tests as well.
  #
  # That results in weird behavior since we run the Bundler APIs with different sets of dependencies. We reset Bundler's
  # entire state before and after to try to minimize any state leaking.
  #
  # We also need to ensure that after each example runs, Bundler is actually setup properly for other tests, otherwise
  # those will fail
  def setup
    Bundler.reset!
  end

  def teardown
    Bundler.reset!
    Bundler.setup
  end

  def test_does_not_create_composed_gemfile_if_ruby_lsp_and_debug_are_in_the_bundle
    in_temp_dir do |dir|
      File.write(File.join(dir, "Gemfile"), <<~GEMFILE)
        source "https://rubygems.org"
        gem "ruby-lsp"
        gem "debug"
      GEMFILE

      capture_subprocess_io do
        Bundler.with_unbundled_env do
          system("bundle install")
          run_script(dir)
          refute_path_exists(".ruby-lsp/Gemfile")
        end
      end
    end
  end

  def test_does_not_create_composed_gemfile_if_all_gems_are_in_the_bundle_for_rails_apps
    in_temp_dir do |dir|
      File.write(File.join(dir, "Gemfile"), <<~GEMFILE)
        source "https://rubygems.org"
        gem "ruby-lsp"
        gem "debug"
        gem "rails"
        gem "ruby-lsp-rails"
      GEMFILE

      capture_subprocess_io do
        Bundler.with_unbundled_env do
          system("bundle install")
          run_script(dir)
          refute_path_exists(".ruby-lsp/Gemfile")
        end
      end
    end
  end

  def test_creates_composed_bundle
    in_temp_dir do |dir|
      File.write(File.join(dir, "Gemfile"), <<~GEMFILE)
        source "https://rubygems.org"
      GEMFILE

      capture_subprocess_io do
        Bundler.with_unbundled_env do
          system("bundle install")
          run_script(dir)

          assert_path_exists(".ruby-lsp")
          assert_path_exists(".ruby-lsp/Gemfile")
          assert_path_exists(".ruby-lsp/Gemfile.lock")
          assert_path_exists(".ruby-lsp/main_lockfile_hash")
          assert_match("ruby-lsp", File.read(".ruby-lsp/Gemfile"))
          assert_match("debug", File.read(".ruby-lsp/Gemfile"))
          refute_match("ruby-lsp-rails", File.read(".ruby-lsp/Gemfile"))
        end
      end
    end
  end

  def test_creates_composed_bundle_for_a_rails_app
    in_temp_dir do |dir|
      File.write(File.join(dir, "Gemfile"), <<~GEMFILE)
        source "https://rubygems.org"
        gem "rails"
      GEMFILE

      FileUtils.mkdir("#{dir}/config")
      FileUtils.cp("#{__dir__}/fixtures/rails_application.rb", "#{dir}/config/application.rb")

      capture_subprocess_io do
        Bundler.with_unbundled_env do
          system("bundle install")
          run_script(dir)

          assert_path_exists(".ruby-lsp")
          assert_path_exists(".ruby-lsp/Gemfile")
          assert_path_exists(".ruby-lsp/Gemfile.lock")
          assert_path_exists(".ruby-lsp/main_lockfile_hash")
          assert_match("ruby-lsp", File.read(".ruby-lsp/Gemfile"))
          assert_match("debug", File.read(".ruby-lsp/Gemfile"))
          assert_match("ruby-lsp-rails", File.read(".ruby-lsp/Gemfile"))
        end
      end
    end
  end

  def test_changing_lockfile_causes_composed_bundle_to_be_rebuilt
    in_temp_dir do |dir|
      File.write(File.join(dir, "Gemfile"), <<~GEMFILE)
        source "https://rubygems.org"
        gem "rdoc"
      GEMFILE

      capture_subprocess_io do
        Bundler.with_unbundled_env do
          # Run bundle install to generate the lockfile
          system("bundle install")

          # Run the script once to generate a composed bundle
          run_script(dir)
        end
      end

      capture_subprocess_io do
        Bundler.with_unbundled_env do
          # Add a new dependency to the Gemfile
          File.write(File.join(dir, "Gemfile"), <<~GEMFILE)
            source "https://rubygems.org"
            gem "rdoc"
            gem "irb"
          GEMFILE

          # Run bundle install to generate the lockfile. This will generate a new lockfile that won't match the stored
          # SHA
          system("bundle install")
        end
      end

      # At this point, the composed bundle includes the `ruby-lsp` in its lockfile, but that will be overwritten when
      # we copy the top level lockfile. If composed bundle dependencies are eagerly evaluated, then we would think the
      # ruby-lsp is a part of the composed lockfile and would try to run `bundle update ruby-lsp`, which would fail.
      # If we evaluate lazily, then we only find dependencies after the lockfile was copied, and then run bundle
      # install instead, which re-locks and adds the ruby-lsp
      Bundler.with_unbundled_env do
        run_script(dir)
      end
    end
  end

  def test_does_not_copy_gemfile_lock_when_not_modified
    in_temp_dir do |dir|
      File.write(File.join(dir, "Gemfile"), <<~GEMFILE)
        source "https://rubygems.org"
        gem "rdoc"
      GEMFILE

      capture_subprocess_io do
        Bundler.with_unbundled_env do
          # Run bundle install to generate the lockfile
          system("bundle install")

          # Run the script once to generate a composed bundle
          run_script(dir)
        end
      end

      FileUtils.touch("Gemfile.lock", mtime: Time.now + 10 * 60)

      capture_subprocess_io do
        Bundler.with_unbundled_env do
          stub_bundle_with_env(
            bundle_env(dir, ".ruby-lsp/Gemfile"),
            /((bundle _[\d\.]+_ check && bundle _[\d\.]+_ update ruby-lsp debug prism rbs) || bundle _[\d\.]+_ install) 1>&2/,
          )

          FileUtils.expects(:cp).never

          # Run the script again without having the lockfile modified
          run_script(dir)
        end
      end
    end
  end

  def test_does_only_updates_every_4_hours
    in_temp_dir do |dir|
      File.write(File.join(dir, "Gemfile"), <<~GEMFILE)
        source "https://rubygems.org"
        gem "rdoc"
      GEMFILE

      capture_subprocess_io do
        Bundler.with_unbundled_env do
          # Run bundle install to generate the lockfile
          system("bundle install")

          # Run the script once to generate a composed bundle
          run_script(dir)
        end
      end

      File.write(File.join(dir, ".ruby-lsp", "last_updated"), (Time.now - 30 * 60).iso8601)

      capture_subprocess_io do
        Bundler.with_unbundled_env do
          stub_bundle_with_env(bundle_env(dir, ".ruby-lsp/Gemfile"))
          # Run the script again without having the lockfile modified
          run_script(dir)
        end
      end
    end
  end

  def test_uses_absolute_bundle_path_for_bundle_install
    in_temp_dir do |dir|
      File.write(File.join(dir, "Gemfile"), <<~GEMFILE)
        source "https://rubygems.org"
      GEMFILE

      capture_subprocess_io do
        Bundler.with_unbundled_env do
          system("bundle", "config", "set", "--local", "path", "vendor/bundle")
          system("bundle", "install")
          run_script(expected_path: File.expand_path("vendor/bundle", Dir.pwd))
        end
      end
    end
  end

  def test_creates_composed_bundle_if_no_gemfile
    in_temp_dir do |dir|
      capture_subprocess_io do
        Bundler.with_unbundled_env do
          run_script(dir)
        end
      end

      assert_path_exists(".ruby-lsp")
      assert_path_exists(".ruby-lsp/Gemfile")
      assert_match("ruby-lsp", File.read(".ruby-lsp/Gemfile"))
      assert_match("debug", File.read(".ruby-lsp/Gemfile"))
    end
  end

  def test_raises_if_bundle_is_not_locked
    # Create a temporary directory with no Gemfile or Gemfile.lock
    in_temp_dir do |dir|
      FileUtils.touch("Gemfile")

      Bundler.with_unbundled_env do
        assert_raises(RubyLsp::SetupBundler::BundleNotLocked) do
          run_script(dir)
        end
      end
    end
  end

  def test_does_not_create_composed_gemfile_if_both_ruby_lsp_and_debug_are_gemspec_dependencies
    in_temp_dir do |dir|
      # Write a fake Gemfile and gemspec
      File.write(File.join(dir, "Gemfile"), <<~GEMFILE)
        source "https://rubygems.org"
        gemspec
      GEMFILE

      File.write(File.join(dir, "fake.gemspec"), <<~GEMSPEC)
        Gem::Specification.new do |s|
          s.name = "fake"
          s.version = "0.1.0"
          s.authors = ["Dev"]
          s.email = ["dev@example.com"]
          s.metadata["allowed_push_host"] = "https://rubygems.org"

          s.summary = "A fake gem"
          s.description = "A fake gem"
          s.homepage = "https://github.com/fake/gem"
          s.license = "MIT"
          s.files = Dir.glob("lib/**/*.rb") + ["README.md", "VERSION", "LICENSE.txt"]
          s.bindir = "exe"
          s.require_paths = ["lib"]

          s.add_dependency("ruby-lsp")
          s.add_dependency("debug")
        end
      GEMSPEC

      FileUtils.touch(File.join(dir, "Gemfile.lock"))

      capture_subprocess_io do
        Bundler.with_unbundled_env do
          system("bundle", "install")
          run_script(dir)
          refute_path_exists(".ruby-lsp/Gemfile")
        end
      end
    end
  end

  def test_creates_composed_bundle_with_specified_branch
    in_temp_dir do |dir|
      Bundler.with_unbundled_env do
        stub_bundle_with_env(bundle_env(dir, ".ruby-lsp/Gemfile"))
        run_script(File.realpath(dir), branch: "test-branch")
      end

      assert_path_exists(".ruby-lsp")
      assert_path_exists(".ruby-lsp/Gemfile")
      assert_match(%r{ruby-lsp.*github: "Shopify/ruby-lsp", branch: "test-branch"}, File.read(".ruby-lsp/Gemfile"))
      assert_match("debug", File.read(".ruby-lsp/Gemfile"))
    end
  end

  def test_returns_bundle_app_config_if_there_is_local_config
    in_temp_dir do |dir|
      Bundler.with_unbundled_env do
        Bundler.settings.temporary(without: "production") do
          stub_bundle_with_env(bundle_env(dir, ".ruby-lsp/Gemfile"))

          run_script(File.realpath(dir))
        end
      end
    end
  end

  def test_composed_bundle_uses_alternative_gemfiles
    in_temp_dir do |dir|
      File.write(File.join(dir, "gems.rb"), <<~GEMFILE)
        source "https://rubygems.org"
        gem "rdoc"
      GEMFILE

      Bundler.with_unbundled_env do
        capture_subprocess_io do
          system("bundle install")
          run_script(dir)
        end
      end

      assert_path_exists(".ruby-lsp")
      assert_path_exists(".ruby-lsp/gems.rb")
      assert_path_exists(".ruby-lsp/gems.locked")
      assert_match("debug", File.read(".ruby-lsp/gems.rb"))
      assert_match("ruby-lsp", File.read(".ruby-lsp/gems.rb"))
      assert_match("eval_gemfile(File.expand_path(\"../gems.rb\", __dir__))", File.read(".ruby-lsp/gems.rb"))
    end
  end

  def test_composed_bundle_points_to_gemfile_in_enclosing_dir
    Dir.mktmpdir do |dir|
      FileUtils.touch(File.join(dir, "Gemfile"))
      FileUtils.touch(File.join(dir, "Gemfile.lock"))

      project_dir = File.join(dir, "proj")
      Dir.mkdir(project_dir)

      Dir.chdir(project_dir) do
        Bundler.with_unbundled_env do
          run_script(project_dir)
        end

        assert_path_exists(".ruby-lsp/Gemfile")
        assert_match("eval_gemfile(File.expand_path(\"../../Gemfile\", __dir__))", File.read(".ruby-lsp/Gemfile"))
      end
    end
  end

  def test_ensures_lockfile_remotes_are_relative_to_default_gemfile
    in_temp_dir do |dir|
      # The structure used in Rails uncovered a bug in our composed bundle logic. Rails is an empty gem with a bunch
      # of nested gems. The lockfile includes remotes that use relative paths and we need to adjust those when we copy
      # the lockfile

      File.write(File.join(dir, "Gemfile"), <<~GEMFILE)
        # frozen_string_literal: true
        source "https://rubygems.org"
        gemspec
        gem "importmap-rails", ">= 1.2.3"
      GEMFILE

      FileUtils.mkdir(File.join(dir, "lib"))
      FileUtils.mkdir_p(File.join(dir, "activesupport", "lib"))

      File.write(File.join(dir, "activesupport", "activesupport.gemspec"), <<~GEMSPEC)
        Gem::Specification.new do |s|
          s.platform    = Gem::Platform::RUBY
          s.name        = "activesupport"
          s.version     = "7.2.0.alpha"
          s.summary     = "Nested gemspec"
          s.description = "Nested gemspec"
          s.license = "MIT"
          s.author   = "User"
          s.email    = "user@example.com"
          s.homepage = "https://rubyonrails.org"
          s.files        = Dir["CHANGELOG.md", "MIT-LICENSE", "README.rdoc", "lib/**/*"]
          s.require_path = "lib"
          s.add_dependency "i18n",            ">= 1.6", "< 2"
          s.add_dependency "tzinfo",          "~> 2.0", ">= 2.0.5"
          s.add_dependency "concurrent-ruby", "~> 1.0", ">= 1.0.2"
          s.add_dependency "connection_pool", ">= 2.2.5"
          s.add_dependency "minitest",        ">= 5.1"
          s.add_dependency "base64"
          s.add_dependency "drb"
          s.add_dependency "bigdecimal"
        end
      GEMSPEC

      File.write(File.join(dir, "activesupport", "Gemfile"), <<~GEMFILE)
        source "https://rubygems.org"
      GEMFILE

      File.write(File.join(dir, "rails.gemspec"), <<~GEMSPEC)
        Gem::Specification.new do |s|
          s.platform    = Gem::Platform::RUBY
          s.name        = "rails"
          s.version     = "7.2.0.alpha"
          s.summary     = "Top level gem"
          s.description = "Top level gem"
          s.license = "MIT"
          s.author   = "User"
          s.email    = "user@example.com"
          s.homepage = "https://rubyonrails.org"
          s.files = ["README.md", "MIT-LICENSE"]
          s.add_dependency "activesupport", "7.2.0.alpha"
        end
      GEMSPEC

      Bundler.with_unbundled_env do
        capture_subprocess_io do
          system("bundle install")
          run_script(File.realpath(dir))
        end
      end

      assert_path_exists(".ruby-lsp")
      assert_path_exists(".ruby-lsp/Gemfile.lock")
      assert_match("remote: ..", File.read(".ruby-lsp/Gemfile.lock"))
    end
  end

  def test_ensures_lockfile_remotes_are_absolute_in_projects_with_nested_gems
    in_temp_dir do |dir|
      File.write(File.join(dir, "Gemfile"), <<~GEMFILE)
        # frozen_string_literal: true
        source "https://rubygems.org"
        gem "nested", path: "gems/nested"
      GEMFILE

      FileUtils.mkdir_p(File.join(dir, "gems", "nested", "lib"))

      File.write(File.join(dir, "gems", "nested", "nested.gemspec"), <<~GEMSPEC)
        Gem::Specification.new do |s|
          s.platform    = Gem::Platform::RUBY
          s.name        = "nested"
          s.version     = "1.0.0"
          s.summary     = "Nested gemspec"
          s.description = "Nested gemspec"
          s.license = "MIT"
          s.author   = "User"
          s.email    = "user@example.com"
          s.homepage = "https://rubyonrails.org"
          s.files        = Dir[]
          s.require_path = "lib"
        end
      GEMSPEC

      File.write(File.join(dir, "gems", "nested", "Gemfile"), <<~GEMFILE)
        source "https://rubygems.org"
        gemspec
      GEMFILE

      real_path = File.realpath(dir)

      Bundler.with_unbundled_env do
        capture_subprocess_io do
          system("bundle install")
          run_script(real_path)
        end
      end

      assert_path_exists(".ruby-lsp")
      assert_path_exists(".ruby-lsp/Gemfile.lock")
      assert_match("remote: #{File.join(real_path, "gems", "nested")}", File.read(".ruby-lsp/Gemfile.lock"))
    end
  end

  def test_ruby_lsp_rails_is_automatically_included_in_rails_apps
    in_temp_dir do |dir|
      FileUtils.mkdir("#{dir}/config")
      FileUtils.cp("#{__dir__}/fixtures/rails_application.rb", "#{dir}/config/application.rb")
      File.write(File.join(dir, "Gemfile"), <<~GEMFILE)
        source "https://rubygems.org"
        gem "rails"
      GEMFILE

      capture_subprocess_io do
        Bundler.with_unbundled_env do
          # Run bundle install to generate the lockfile
          system("bundle install")
          run_script(dir)
        end
      end

      assert_path_exists(".ruby-lsp/Gemfile")
      assert_match('gem "ruby-lsp-rails"', File.read(".ruby-lsp/Gemfile"))
    end
  end

  def test_ruby_lsp_rails_detection_handles_lang_from_environment
    with_default_external_encoding("us-ascii") do
      in_temp_dir do |dir|
        FileUtils.mkdir("#{dir}/config")
        FileUtils.cp("#{__dir__}/fixtures/rails_application.rb", "#{dir}/config/application.rb")

        File.write(File.join(dir, "Gemfile"), <<~GEMFILE)
          source "https://rubygems.org"
          gem "rails"
        GEMFILE

        capture_subprocess_io do
          Bundler.with_unbundled_env do
            # Run bundle install to generate the lockfile
            system("bundle install")
            run_script(dir)
          end
        end

        assert_path_exists(".ruby-lsp/Gemfile")
        assert_match('gem "ruby-lsp-rails"', File.read(".ruby-lsp/Gemfile"))
      end
    end
  end

  def test_recovers_from_stale_lockfiles
    in_temp_dir do |dir|
      custom_dir = File.join(dir, ".ruby-lsp")
      FileUtils.mkdir_p(custom_dir)

      # Write the main Gemfile and lockfile with valid versions
      File.write(File.join(dir, "Gemfile"), <<~GEMFILE)
        source "https://rubygems.org"
        gem "stringio"
      GEMFILE

      lockfile_contents = <<~LOCKFILE
        GEM
          remote: https://rubygems.org/
          specs:
            stringio (3.1.0)

        PLATFORMS
          arm64-darwin-23
          ruby

        DEPENDENCIES
          stringio

        BUNDLED WITH
          2.5.7
      LOCKFILE
      File.write(File.join(dir, "Gemfile.lock"), lockfile_contents)

      # Write the lockfile hash based on the valid file
      File.write(File.join(custom_dir, "main_lockfile_hash"), Digest::SHA256.hexdigest(lockfile_contents))

      # Write the composed bundle's lockfile using a fake version that doesn't exist to force bundle install to fail
      File.write(File.join(custom_dir, "Gemfile"), <<~GEMFILE)
        source "https://rubygems.org"
        gem "stringio"
      GEMFILE
      File.write(File.join(custom_dir, "Gemfile.lock"), <<~LOCKFILE)
        GEM
          remote: https://rubygems.org/
          specs:
            stringio (999.1.555)

        PLATFORMS
          arm64-darwin-23
          ruby

        DEPENDENCIES
          stringio

        BUNDLED WITH
          2.5.7
      LOCKFILE

      Bundler.with_unbundled_env do
        run_script(dir)
      end

      # Verify that the script recovered and re-generated the composed bundle from scratch
      assert_path_exists(".ruby-lsp/Gemfile")
      assert_path_exists(".ruby-lsp/Gemfile.lock")
      refute_match("999.1.555", File.read(".ruby-lsp/Gemfile.lock"))
    end
  end

  def test_respects_overridden_bundle_path_when_there_is_bundle_config
    in_temp_dir do |dir|
      File.write(File.join(dir, "gems.rb"), <<~GEMFILE)
        source "https://rubygems.org"
        gem "irb"
      GEMFILE

      Bundler.with_unbundled_env do
        vendor_path = File.join(dir, "vendor", "bundle")

        system("bundle", "config", "set", "--local", "path", File.join("vendor", "bundle"))
        assert_path_exists(File.join(dir, ".bundle", "config"))

        capture_subprocess_io do
          system("bundle install")
          assert_path_exists(vendor_path)

          run_script(dir)
        end
      end

      refute_path_exists(File.join(dir, ".ruby-lsp", "vendor"))
    end
  end

  def test_uses_correct_bundler_env_when_there_is_bundle_config
    in_temp_dir do |dir|
      File.write(File.join(dir, "Gemfile"), <<~GEMFILE)
        source "https://rubygems.org"
        gem "irb"
      GEMFILE

      Bundler.with_unbundled_env do
        system("bundle config set --local with production staging")

        assert_path_exists(File.join(dir, ".bundle", "config"))

        capture_subprocess_io do
          system("bundle install")

          env = run_script(dir)

          assert_equal("production:staging", env["BUNDLE_WITH"])
        end
      end
    end
  end

  def test_sets_bundler_version_to_avoid_reloads
    in_temp_dir do |dir|
      # Write the main Gemfile and lockfile with valid versions
      File.write(File.join(dir, "Gemfile"), <<~GEMFILE)
        source "https://rubygems.org"
        gem "stringio"
      GEMFILE

      lockfile_contents = <<~LOCKFILE
        GEM
          remote: https://rubygems.org/
          specs:
            stringio (3.1.0)

        PLATFORMS
          arm64-darwin-23
          ruby

        DEPENDENCIES
          stringio

        BUNDLED WITH
          2.5.7
      LOCKFILE
      File.write(File.join(dir, "Gemfile.lock"), lockfile_contents)

      Bundler.with_unbundled_env do
        env = run_script(dir)
        assert_equal("2.5.7", env["BUNDLER_VERSION"])
      end

      lockfile_parser = Bundler::LockfileParser.new(File.read(File.join(dir, ".ruby-lsp", "Gemfile.lock")))
      assert_equal("2.5.7", lockfile_parser.bundler_version.to_s)
    end
  end

  def test_invoke_cli_calls_bundler_directly_for_install
    in_temp_dir do |dir|
      File.write(File.join(dir, "gems.rb"), <<~GEMFILE)
        source "https://rubygems.org"
        gem "irb"
      GEMFILE

      Bundler.with_unbundled_env do
        capture_subprocess_io do
          system("bundle install")

          mock_install = mock("install")
          mock_install.expects(:run)
          Bundler::CLI::Install.expects(:new).with({ "no-cache" => true }).returns(mock_install)

          compose = RubyLsp::SetupBundler.new(dir, launcher: true)
          compose.expects(:bundle_check).raises(StandardError, "missing gems")
          compose.setup!
        end
      end
    end
  end

  def test_invoke_cli_calls_bundler_directly_for_update
    in_temp_dir do |dir|
      File.write(File.join(dir, "Gemfile"), <<~GEMFILE)
        source "https://rubygems.org"
        gem "rdoc"
      GEMFILE

      capture_subprocess_io do
        Bundler.with_unbundled_env do
          # Run bundle install to generate the lockfile
          system("bundle install")

          # Run the script once to generate a custom bundle
          run_script(dir)
        end
      end

      capture_subprocess_io do
        Bundler.with_unbundled_env do
          mock_update = mock("update")
          mock_update.expects(:run)
          require "bundler/cli/update"
          Bundler::CLI::Update.expects(:new).with(
            { conservative: true },
            ["ruby-lsp", "debug", "prism", "rbs"],
          ).returns(mock_update)

          FileUtils.touch(File.join(dir, ".ruby-lsp", "needs_update"))
          RubyLsp::SetupBundler.new(dir, launcher: true).setup!
        end
      end
    end
  end

  def test_progress_is_printed_to_stderr
    in_temp_dir do |dir|
      File.write(File.join(dir, "Gemfile"), <<~GEMFILE)
        source "https://rubygems.org"
        gem "rdoc"
      GEMFILE

      File.write(File.join(dir, "Gemfile.lock"), <<~LOCKFILE)
        GEM
          remote: https://rubygems.org/
          specs:
            date (3.5.0)
            erb (6.0.0)
            psych (5.2.6)
              date
              stringio
            rdoc (6.16.0)
              erb
              psych (>= 4.0.0)
              tsort
            stringio (3.1.8)
            tsort (0.2.0)

        PLATFORMS
          arm64-darwin-23
          ruby

        DEPENDENCIES
          rdoc

        CHECKSUMS
          date (3.5.0) sha256=5e74fd6c04b0e65d97ad4f3bb5cb2d8efb37f386cc848f46310b4593ffc46ee5
          erb (6.0.0) sha256=2730893f9d8c9733f16cab315a4e4b71c1afa9cabc1a1e7ad1403feba8f52579
          psych (5.2.6) sha256=814328aa5dcb6d604d32126a20bc1cbcf05521a5b49dbb1a8b30a07e580f316e
          rdoc (6.16.0) sha256=d0ce6f787027a24e480c1acb9f3110125213cb5df6806fd7832d5a1b8f26a205
          stringio (3.1.8) sha256=99c43c3a9302843cca223fd985bfc503dd50a4b1723d3e4a9eb1d9c37d99e4ec
          tsort (0.2.0) sha256=9650a793f6859a43b6641671278f79cfead60ac714148aabe4e3f0060480089f

        BUNDLED WITH
          4.0.0.beta2
      LOCKFILE

      gem_mock = mock("gem")
      gem_mock.expects(:name).returns("rdoc")
      gem_mock.expects(:version).returns("6.16.0")

      Bundler.with_unbundled_env do
        stdout, stderr = capture_subprocess_io do
          compose = RubyLsp::SetupBundler.new(dir, launcher: true)
          compose.expects(:bundle_check).returns([gem_mock])
          compose.setup!
        end

        assert_match(/Bundle complete!/, stderr)
        assert_empty(stdout)
      end
    end
  end

  def test_succeeds_when_using_ssh_git_sources_instead_of_https
    in_temp_dir do |dir|
      File.write(File.join(dir, "Gemfile"), <<~GEMFILE)
        source "https://rubygems.org"
        gem "rbi", git: "git@github.com:Shopify/rbi.git", branch: "main"
      GEMFILE

      File.write(File.join(dir, "Gemfile.lock"), <<~LOCKFILE)
        GIT
          remote: git@github.com:Shopify/rbi.git
          revision: d2e59a207c0b2f07d9bbaf1eb4b6d2500a4782ea
          branch: main
          specs:
            rbi (0.2.1)
              prism (~> 1.0)
              sorbet-runtime (>= 0.5.9204)

        GEM
          remote: https://rubygems.org/
          specs:
            prism (1.2.0)
            sorbet-runtime (0.5.11630)

        PLATFORMS
          arm64-darwin-23
          ruby

        DEPENDENCIES
          rbi!

        BUNDLED WITH
          2.5.22
      LOCKFILE

      Bundler.with_unbundled_env do
        capture_subprocess_io do
          stub_bundle_with_env(bundle_env(dir, ".ruby-lsp/Gemfile"))
          run_script(dir)
        end
      end

      assert_match("remote: git@github.com:Shopify/rbi.git", File.read(".ruby-lsp/Gemfile.lock"))
    end
  end

  def test_is_resilient_to_gemfile_changes_in_the_middle_of_setup
    in_temp_dir do |dir|
      File.write(File.join(dir, "Gemfile"), <<~GEMFILE)
        source "https://rubygems.org"
        gem "rdoc"
      GEMFILE

      Bundler.with_unbundled_env do
        capture_subprocess_io do
          # Run bundle install to generate the lockfile
          system("bundle install")

          # This section simulates the bundle being modified during the composed bundle setup. We initialize the
          # composed bundle first to eagerly calculate the gemfile and lockfile hashes. Then we modify the Gemfile
          # afterwards and trigger the setup.
          #
          # This type of scenario may happen if someone switches branches in the middle of running bundle install. By
          # the time we finish, the bundle may be in a different state and we need to recover from that
          composed_bundle = RubyLsp::SetupBundler.new(dir, launcher: true)

          File.write(File.join(dir, "Gemfile"), <<~GEMFILE)
            source "https://rubygems.org"
            gem "rdoc"
            gem "irb"
          GEMFILE
          system("bundle install")

          composed_bundle.setup!
        end

        assert_match("irb", File.read(".ruby-lsp/Gemfile.lock"))
      end
    end
  end

  def test_only_returns_environment_if_bundle_was_composed_ahead_of_time
    in_temp_dir do |dir|
      FileUtils.mkdir(".ruby-lsp")
      FileUtils.touch(File.join(".ruby-lsp", "bundle_is_composed"))

      require "bundler/cli/update"
      require "bundler/cli/install"
      Bundler::CLI::Update.expects(:new).never
      Bundler::CLI::Install.expects(:new).never

      assert_output("", "Ruby LSP> Composed bundle was set up ahead of time. Skipping...\n") do
        refute_empty(RubyLsp::SetupBundler.new(dir, launcher: true).setup!)
      end
    end
  end

  def test_ignores_bundle_package
    in_temp_dir do |dir|
      File.write(File.join(dir, "Gemfile"), <<~GEMFILE)
        source "https://rubygems.org"
        gem "irb"
      GEMFILE

      capture_subprocess_io do
        Bundler.with_unbundled_env do
          system("bundle", "install")
          system("bundle", "package")

          env = RubyLsp::SetupBundler.new(dir, launcher: true).setup!
          refute_includes(env.keys, "BUNDLE_CACHE_ALL")
          refute_includes(env.keys, "BUNDLE_CACHE_ALL_PLATFORMS")
        end
      end
    end
  end

  def test_handles_network_down_error_during_bundle_install
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        File.write(File.join(dir, "gems.rb"), <<~GEMFILE)
          source "https://rubygems.org"
          gem "irb"
        GEMFILE

        Bundler.with_unbundled_env do
          capture_subprocess_io do
            system("bundle install")

            compose = RubyLsp::SetupBundler.new(dir, launcher: true)
            compose.expects(:bundle_check).raises(Bundler::Fetcher::NetworkDownError)
            compose.setup!

            refute_path_exists(File.join(dir, ".ruby-lsp", "install_error"))
          end
        end
      end
    end
  end

  def test_handles_http_error_during_bundle_install
    in_temp_dir do |dir|
      File.write(File.join(dir, "gems.rb"), <<~GEMFILE)
        source "https://rubygems.org"
        gem "irb"
      GEMFILE

      Bundler.with_unbundled_env do
        capture_subprocess_io do
          system("bundle install")

          compose = RubyLsp::SetupBundler.new(dir, launcher: true)
          compose.expects(:bundle_check).raises(Bundler::HTTPError)
          compose.setup!

          refute_path_exists(File.join(dir, ".ruby-lsp", "install_error"))
        end
      end
    end
  end

  def test_is_resilient_to_pipe_being_closed_by_client_during_compose
    in_temp_dir do |dir|
      File.write(File.join(dir, "gems.rb"), <<~GEMFILE)
        source "https://rubygems.org"
        gem "irb"
      GEMFILE

      Bundler.with_unbundled_env do
        capture_subprocess_io do
          system("bundle install")

          compose = RubyLsp::SetupBundler.new(dir, launcher: true)
          compose.expects(:run_bundle_install_directly).raises(Errno::EPIPE)
          compose.setup!
          refute_path_exists(File.join(dir, ".ruby-lsp", "install_error"))
        end
      end
    end
  end

  private

  def in_temp_dir(&block)
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        block.call(dir)
      end
    end
  end

  def with_default_external_encoding(encoding, &block)
    ignore_warnings do
      original_encoding = Encoding.default_external
      begin
        Encoding.default_external = encoding
        block.call
      ensure
        Encoding.default_external = original_encoding
      end
    end
  end

  def ignore_warnings(&block)
    # Since overwriting the encoding emits a warning
    previous = $VERBOSE
    $VERBOSE = nil

    begin
      block.call
    ensure
      $VERBOSE = previous
    end
  end

  # This method runs the script and then immediately unloads it. This allows us to make assertions against the effects
  # of running the script multiple times
  def run_script(path = Dir.pwd, expected_path: nil, **options)
    env = {} #: Hash[String, String]

    stdout, _stderr = capture_subprocess_io do
      env = RubyLsp::SetupBundler.new(File.realpath(path), **options).setup!
      assert_equal(expected_path, env["BUNDLE_PATH"]) if expected_path
    end

    assert_empty(stdout)
    env
  end

  # This method needs to be called inside the `Bundler.with_unbundled_env` block IF the command you want to test is
  # inside it.
  def stub_bundle_with_env(
    env,
    command = /(bundle check _[\d\.]+_ || bundle _[\d\.]+_ install) 1>&2/
  )
    Object.any_instance.expects(:system).with do |actual_env, actual_command|
      actual_env.delete_if { |k, _v| k.start_with?("BUNDLE_PKGS") || k == "BUNDLER_VERSION" }
      actual_env.all? { |k, v| env[k] == v } && actual_command.match?(command)
    end.returns(true)
  end

  def bundle_env(base_path = Dir.pwd, bundle_gemfile = "Gemfile")
    expanded_base_path = File.realpath(base_path)

    settings = begin
      local_config_path = File.join(base_path, ".bundle")
      Dir.exist?(local_config_path) ? Bundler::Settings.new(local_config_path) : Bundler::Settings.new
    rescue Bundler::GemfileNotFound
      Bundler::Settings.new
    end

    env = settings.all.to_h do |e|
      key = settings.key_for(e)
      value = Array(settings[e]).join(":").tr(" ", ":")

      [key, value]
    end

    if env["BUNDLE_PATH"]
      env["BUNDLE_PATH"] = File.expand_path(env["BUNDLE_PATH"], expanded_base_path)
    end

    env["BUNDLE_GEMFILE"] = File.join(expanded_base_path, bundle_gemfile)
    env
  end
end
