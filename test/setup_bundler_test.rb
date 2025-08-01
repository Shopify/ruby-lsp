# typed: true
# frozen_string_literal: true

require "test_helper"
require "ruby_lsp/setup_bundler"

class SetupBundlerTest < Minitest::Test
  def test_does_not_create_composed_gemfile_if_ruby_lsp_and_debug_are_in_the_bundle
    stub_bundle_with_env(bundle_env)
    Bundler::LockfileParser.any_instance.expects(:dependencies).returns({ "ruby-lsp" => true, "debug" => true })
    run_script
    refute_path_exists(".ruby-lsp/Gemfile")
  end

  def test_does_not_create_composed_gemfile_if_all_gems_are_in_the_bundle_for_rails_apps
    stub_bundle_with_env(bundle_env)
    Bundler::LockfileParser.any_instance.expects(:dependencies).returns({
      "ruby-lsp" => true,
      "rails" => true,
      "ruby-lsp-rails" => true,
      "debug" => true,
    })
    run_script
    refute_path_exists(".ruby-lsp/Gemfile")
  end

  def test_creates_composed_bundle
    stub_bundle_with_env(bundle_env(Dir.pwd, ".ruby-lsp/Gemfile"))
    Bundler::LockfileParser.any_instance.expects(:dependencies).returns({}).at_least_once
    run_script

    assert_path_exists(".ruby-lsp")
    assert_path_exists(".ruby-lsp/Gemfile")
    assert_path_exists(".ruby-lsp/Gemfile.lock")
    assert_path_exists(".ruby-lsp/main_lockfile_hash")
    assert_match("ruby-lsp", File.read(".ruby-lsp/Gemfile"))
    refute_match("ruby-lsp-rails", File.read(".ruby-lsp/Gemfile"))
    assert_match("debug", File.read(".ruby-lsp/Gemfile"))
  ensure
    FileUtils.rm_r(".ruby-lsp") if Dir.exist?(".ruby-lsp")
  end

  def test_creates_composed_bundle_for_a_rails_app
    stub_bundle_with_env(bundle_env(Dir.pwd, ".ruby-lsp/Gemfile"))
    FileUtils.mkdir("config")
    FileUtils.cp("test/fixtures/rails_application.rb", "config/application.rb")
    Bundler::LockfileParser.any_instance.expects(:dependencies).returns({ "rails" => true }).at_least_once
    run_script

    assert_path_exists(".ruby-lsp")
    assert_path_exists(".ruby-lsp/Gemfile")
    assert_path_exists(".ruby-lsp/Gemfile.lock")
    assert_path_exists(".ruby-lsp/main_lockfile_hash")
    assert_match("ruby-lsp", File.read(".ruby-lsp/Gemfile"))
    assert_match("debug", File.read(".ruby-lsp/Gemfile"))
    assert_match("ruby-lsp-rails", File.read(".ruby-lsp/Gemfile"))
  ensure
    FileUtils.rm_r(".ruby-lsp") if Dir.exist?(".ruby-lsp")
    FileUtils.rm_r("config") if Dir.exist?("config")
  end

  def test_changing_lockfile_causes_composed_bundle_to_be_rebuilt
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
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
          stub_bundle_with_env(bundle_env(dir, ".ruby-lsp/Gemfile"))
          run_script(dir)
        end
      end
    end
  end

  def test_does_not_copy_gemfile_lock_when_not_modified
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
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
              /((bundle _[\d\.]+_ check && bundle _[\d\.]+_ update ruby-lsp debug) || bundle _[\d\.]+_ install) 1>&2/,
            )

            FileUtils.expects(:cp).never

            # Run the script again without having the lockfile modified
            run_script(dir)
          end
        end
      end
    end
  end

  def test_does_only_updates_every_4_hours
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
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
  end

  def test_uses_absolute_bundle_path_for_bundle_install
    original = Bundler.settings[:path]
    Bundler.settings.set_global(:path, "vendor/bundle")

    stub_bundle_with_env(bundle_env(Dir.pwd, ".ruby-lsp/Gemfile"))

    Bundler::LockfileParser.any_instance.expects(:dependencies).returns({}).at_least_once
    run_script(expected_path: File.expand_path("vendor/bundle", Dir.pwd))
  ensure
    FileUtils.rm_r(".ruby-lsp")
    Bundler.settings.set_global(:path, original)
  end

  def test_creates_composed_bundle_if_no_gemfile
    # Create a temporary directory with no Gemfile or Gemfile.lock
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        bundle_gemfile = Pathname.new(".ruby-lsp").expand_path(dir) + "Gemfile"

        Bundler.with_unbundled_env do
          stub_bundle_with_env(bundle_env(dir, bundle_gemfile.to_s))
          run_script(dir)
        end

        assert_path_exists(".ruby-lsp")
        assert_path_exists(".ruby-lsp/Gemfile")
        assert_match("ruby-lsp", File.read(".ruby-lsp/Gemfile"))
        assert_match("debug", File.read(".ruby-lsp/Gemfile"))
      end
    end
  end

  def test_raises_if_bundle_is_not_locked
    # Create a temporary directory with no Gemfile or Gemfile.lock
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        FileUtils.touch("Gemfile")

        Bundler.with_unbundled_env do
          assert_raises(RubyLsp::SetupBundler::BundleNotLocked) do
            run_script(dir)
          end
        end
      end
    end
  end

  def test_does_not_create_composed_gemfile_if_both_ruby_lsp_and_debug_are_gemspec_dependencies
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
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

        Bundler.with_unbundled_env do
          stub_bundle_with_env(bundle_env(File.realpath(dir)))
          Bundler::LockfileParser.any_instance.expects(:dependencies).returns({})
          run_script(dir)
        end

        refute_path_exists(".ruby-lsp/Gemfile")
      end
    end
  end

  def test_creates_composed_bundle_with_specified_branch
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        bundle_gemfile = Pathname.new(".ruby-lsp").expand_path(Dir.pwd) + "Gemfile"
        Bundler.with_unbundled_env do
          stub_bundle_with_env(bundle_env(dir, bundle_gemfile.to_s))
          run_script(File.realpath(dir), branch: "test-branch")
        end

        assert_path_exists(".ruby-lsp")
        assert_path_exists(".ruby-lsp/Gemfile")
        assert_match(%r{ruby-lsp.*github: "Shopify/ruby-lsp", branch: "test-branch"}, File.read(".ruby-lsp/Gemfile"))
        assert_match("debug", File.read(".ruby-lsp/Gemfile"))
      end
    end
  end

  def test_returns_bundle_app_config_if_there_is_local_config
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        bundle_gemfile = Pathname.new(".ruby-lsp").expand_path(Dir.pwd) + "Gemfile"
        Bundler.with_unbundled_env do
          Bundler.settings.temporary(without: "production") do
            stub_bundle_with_env(bundle_env(dir, bundle_gemfile.to_s))

            run_script(File.realpath(dir))
          end
        end
      end
    end
  end

  def test_composed_bundle_uses_alternative_gemfiles
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
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
  end

  def test_composed_bundle_points_to_gemfile_in_enclosing_dir
    Dir.mktmpdir do |dir|
      FileUtils.touch(File.join(dir, "Gemfile"))
      FileUtils.touch(File.join(dir, "Gemfile.lock"))

      project_dir = File.join(dir, "proj")
      Dir.mkdir(project_dir)

      Dir.chdir(project_dir) do
        Bundler.with_unbundled_env do
          stub_bundle_with_env(bundle_env(project_dir, ".ruby-lsp/Gemfile"))
          Bundler::LockfileParser.any_instance.expects(:dependencies).returns({}).at_least_once
          run_script(project_dir)
        end

        assert_path_exists(".ruby-lsp/Gemfile")
        assert_match("eval_gemfile(File.expand_path(\"../../Gemfile\", __dir__))", File.read(".ruby-lsp/Gemfile"))
      end
    end
  end

  def test_ensures_lockfile_remotes_are_relative_to_default_gemfile
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
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
  end

  def test_ensures_lockfile_remotes_are_absolute_in_projects_with_nested_gems
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
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
  end

  def test_ruby_lsp_rails_is_automatically_included_in_rails_apps
    Dir.mktmpdir do |dir|
      FileUtils.mkdir("#{dir}/config")
      FileUtils.cp("test/fixtures/rails_application.rb", "#{dir}/config/application.rb")
      Dir.chdir(dir) do
        File.write(File.join(dir, "Gemfile"), <<~GEMFILE)
          source "https://rubygems.org"
          gem "rails"
        GEMFILE

        capture_subprocess_io do
          Bundler.with_unbundled_env do
            # Run bundle install to generate the lockfile
            system("bundle install")
          end
        end

        Bundler.with_unbundled_env do
          stub_bundle_with_env(bundle_env(dir, ".ruby-lsp/Gemfile"))
          run_script(dir)
        end

        assert_path_exists(".ruby-lsp/Gemfile")
        assert_match('gem "ruby-lsp-rails"', File.read(".ruby-lsp/Gemfile"))
      end
    end
  end

  def test_ruby_lsp_rails_detection_handles_lang_from_environment
    with_default_external_encoding("us-ascii") do
      Dir.mktmpdir do |dir|
        FileUtils.mkdir("#{dir}/config")
        FileUtils.cp("test/fixtures/rails_application.rb", "#{dir}/config/application.rb")
        Dir.chdir(dir) do
          File.write(File.join(dir, "Gemfile"), <<~GEMFILE)
            source "https://rubygems.org"
            gem "rails"
          GEMFILE

          capture_subprocess_io do
            Bundler.with_unbundled_env do
              # Run bundle install to generate the lockfile
              system("bundle install")
            end
          end

          Bundler.with_unbundled_env do
            stub_bundle_with_env(bundle_env(dir, ".ruby-lsp/Gemfile"))
            run_script(dir)
          end

          assert_path_exists(".ruby-lsp/Gemfile")
          assert_match('gem "ruby-lsp-rails"', File.read(".ruby-lsp/Gemfile"))
        end
      end
    end
  end

  def test_recovers_from_stale_lockfiles
    Dir.mktmpdir do |dir|
      custom_dir = File.join(dir, ".ruby-lsp")
      FileUtils.mkdir_p(custom_dir)

      Dir.chdir(dir) do
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
  end

  def test_respects_overridden_bundle_path_when_there_is_bundle_config
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        File.write(File.join(dir, "gems.rb"), <<~GEMFILE)
          source "https://rubygems.org"
          gem "irb"
        GEMFILE

        Bundler.with_unbundled_env do
          vendor_path = File.join(dir, "vendor", "bundle")

          system("bundle config --local path #{File.join("vendor", "bundle")}")
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
  end

  def test_uses_correct_bundler_env_when_there_is_bundle_config
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
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
  end

  def test_sets_bundler_version_to_avoid_reloads
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
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
  end

  def test_invoke_cli_calls_bundler_directly_for_install
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
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
  end

  def test_invoke_cli_calls_bundler_directly_for_update
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
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
              ["ruby-lsp", "debug", "prism"],
            ).returns(mock_update)

            FileUtils.touch(File.join(dir, ".ruby-lsp", "needs_update"))
            RubyLsp::SetupBundler.new(dir, launcher: true).setup!
          end
        end
      end
    end
  end

  def test_progress_is_printed_to_stderr
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        File.write(File.join(dir, "Gemfile"), <<~GEMFILE)
          source "https://rubygems.org"
          gem "rdoc"
        GEMFILE

        Bundler.with_unbundled_env do
          capture_subprocess_io do
            # Run bundle install to generate the lockfile
            system("bundle install")
          end

          stdout, stderr = capture_subprocess_io do
            compose = RubyLsp::SetupBundler.new(dir, launcher: true)
            compose.expects(:bundle_check).raises(StandardError, "missing gems")
            compose.setup!
          end

          assert_match(/Bundle complete! [\d]+ Gemfile dependencies, [\d]+ gems now installed/, stderr)
          assert_empty(stdout)
        end
      end
    end
  end

  def test_succeeds_when_using_ssh_git_sources_instead_of_https
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
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
  end

  def test_is_resilient_to_gemfile_changes_in_the_middle_of_setup
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
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
  end

  def test_only_returns_environment_if_bundle_was_composed_ahead_of_time
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
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
  end

  def test_ignores_bundle_bin
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        File.write(File.join(dir, "Gemfile"), <<~GEMFILE)
          source "https://rubygems.org"
          gem "irb"
        GEMFILE

        capture_subprocess_io do
          Bundler.with_unbundled_env do
            system("bundle", "config", "set", "--local", "bin", "bin")
            system("bundle", "install")

            assert_path_exists(File.join(dir, "bin"))

            env = RubyLsp::SetupBundler.new(dir, launcher: true).setup!
            refute_includes(env.keys, "BUNDLE_BIN")
          end
        end
      end
    end
  end

  def test_ignores_bundle_package
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
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
  end

  def test_handles_network_down_error_during_bundle_install
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        File.write(File.join(dir, "gems.rb"), <<~GEMFILE)
          source "https://rubygems.org"
          gem "irb"
        GEMFILE

        Bundler.with_unbundled_env do
          system("bundle install")

          compose = RubyLsp::SetupBundler.new(dir, launcher: true)
          compose.expects(:bundle_check).raises(Bundler::Fetcher::NetworkDownError)
          compose.setup!

          refute_path_exists(File.join(dir, ".ruby-lsp", "install_error"))
        end
      end
    end
  end

  def test_handles_http_error_during_bundle_install
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        File.write(File.join(dir, "gems.rb"), <<~GEMFILE)
          source "https://rubygems.org"
          gem "irb"
        GEMFILE

        Bundler.with_unbundled_env do
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
            compose.expects(:run_bundle_install_directly).raises(Errno::EPIPE)
            compose.setup!
            refute_path_exists(File.join(dir, ".ruby-lsp", "install_error"))
          end
        end
      end
    end
  end

  private

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
      env = RubyLsp::SetupBundler.new(path, **options).setup!
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
    bundle_gemfile_path = Pathname.new(base_path).join(bundle_gemfile)

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
      env["BUNDLE_PATH"] = File.expand_path(env["BUNDLE_PATH"], base_path)
    end

    env["BUNDLE_GEMFILE"] =
      bundle_gemfile_path.absolute? ? bundle_gemfile_path.to_s : bundle_gemfile_path.expand_path(Dir.pwd).to_s

    env
  end
end
