# typed: true
# frozen_string_literal: true

require "test_helper"
require "ruby_lsp/setup_bundler"

class SetupBundlerTest < Minitest::Test
  def test_does_nothing_if_both_ruby_lsp_and_debug_are_in_the_bundle
    Object.any_instance.expects(:system).with(bundle_env, "(bundle check || bundle install) 1>&2").returns(true)
    Bundler::LockfileParser.any_instance.expects(:dependencies).returns({ "ruby-lsp" => true, "debug" => true })
    run_script
    refute_path_exists(".ruby-lsp")
  end

  def test_does_nothing_if_both_ruby_lsp_and_debug_are_in_the_bundle2
    Object.any_instance.expects(:system).with(bundle_env, "(bundle check || bundle install) 1>&2").returns(true)
    Bundler::LockfileParser.any_instance.expects(:dependencies).returns({
      "ruby-lsp" => true,
      "rails" => true,
      "ruby-lsp-rails" => true,
      "debug" => true,
    })
    run_script
    refute_path_exists(".ruby-lsp")
  end

  def test_removes_ruby_lsp_folder_if_both_gems_were_added_to_the_bundle
    Object.any_instance.expects(:system).with(bundle_env, "(bundle check || bundle install) 1>&2")
    Bundler::LockfileParser.any_instance.expects(:dependencies).returns({ "ruby-lsp" => true, "debug" => true })
    FileUtils.mkdir(".ruby-lsp")
    run_script
    refute_path_exists(".ruby-lsp")
  ensure
    FileUtils.rm_r(".ruby-lsp") if Dir.exist?(".ruby-lsp")
  end

  def test_in_a_rails_app_does_nothing_if_ruby_lsp_and_ruby_lsp_rails_and_debug_are_in_the_bundle
    Object.any_instance.expects(:system).with(bundle_env, "(bundle check || bundle install) 1>&2").returns(true)
    Bundler::LockfileParser.any_instance.expects(:dependencies)
      .returns({ "ruby-lsp" => true, "ruby-lsp-rails" => true, "debug" => true })
    run_script
    refute_path_exists(".ruby-lsp")
  ensure
    FileUtils.rm_r(".ruby-lsp") if Dir.exist?(".ruby-lsp")
  end

  def test_in_a_rails_app_removes_ruby_lsp_folder_if_all_gems_were_added_to_the_bundle
    Object.any_instance.expects(:system).with(bundle_env, "(bundle check || bundle install) 1>&2").returns(true)
    Bundler::LockfileParser.any_instance.expects(:dependencies)
      .returns({ "ruby-lsp" => true, "ruby-lsp-rails" => true, "debug" => true })
    FileUtils.mkdir(".ruby-lsp")
    run_script
    refute_path_exists(".ruby-lsp")
  ensure
    FileUtils.rm_r(".ruby-lsp") if Dir.exist?(".ruby-lsp")
  end

  def test_creates_custom_bundle
    Object.any_instance.expects(:system).with(
      bundle_env(".ruby-lsp/Gemfile"),
      "(bundle check || bundle install) 1>&2",
    ).returns(true)
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

  def test_creates_custom_bundle_for_a_rails_app
    Object.any_instance.expects(:system).with(
      bundle_env(".ruby-lsp/Gemfile"),
      "(bundle check || bundle install) 1>&2",
    ).returns(true)
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
  end

  def test_changing_lockfile_causes_custom_bundle_to_be_rebuilt
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
            run_script
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

        # At this point, the custom bundle includes the `ruby-lsp` in its lockfile, but that will be overwritten when we
        # copy the top level lockfile. If custom bundle dependencies are eagerly evaluated, then we would think the
        # ruby-lsp is a part of the custom lockfile and would try to run `bundle update ruby-lsp`, which would fail. If
        # we evaluate lazily, then we only find dependencies after the lockfile was copied, and then run bundle install
        # instead, which re-locks and adds the ruby-lsp
        Object.any_instance.expects(:system).with(
          bundle_env(".ruby-lsp/Gemfile"),
          "(bundle check || bundle install) 1>&2",
        ).returns(true)
        Bundler.with_unbundled_env do
          run_script
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

            # Run the script once to generate a custom bundle
            run_script
          end
        end

        FileUtils.touch("Gemfile.lock", mtime: Time.now + 10 * 60)

        capture_subprocess_io do
          Object.any_instance.expects(:system).with(
            bundle_env(".ruby-lsp/Gemfile"),
            "((bundle check && bundle update ruby-lsp debug) || bundle install) 1>&2",
          ).returns(true)

          FileUtils.expects(:cp).never

          Bundler.with_unbundled_env do
            # Run the script again without having the lockfile modified
            run_script
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

            # Run the script once to generate a custom bundle
            run_script
          end
        end

        File.write(File.join(dir, ".ruby-lsp", "last_updated"), (Time.now - 30 * 60).iso8601)

        capture_subprocess_io do
          Object.any_instance.expects(:system).with(
            bundle_env(".ruby-lsp/Gemfile"),
            "(bundle check || bundle install) 1>&2",
          ).returns(true)

          Bundler.with_unbundled_env do
            # Run the script again without having the lockfile modified
            run_script
          end
        end
      end
    end
  end

  def test_uses_absolute_bundle_path_for_bundle_install
    Bundler.settings.temporary(path: "vendor/bundle") do
      Object.any_instance.expects(:system).with(
        bundle_env(".ruby-lsp/Gemfile"),
        "(bundle check || bundle install) 1>&2",
      ).returns(true)
      Bundler::LockfileParser.any_instance.expects(:dependencies).returns({}).at_least_once
      run_script(expected_path: File.expand_path("vendor/bundle", Dir.pwd))
    end
  ensure
    FileUtils.rm_r(".ruby-lsp")
  end

  def test_creates_custom_bundle_if_no_gemfile
    # Create a temporary directory with no Gemfile or Gemfile.lock
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        bundle_gemfile = Pathname.new(".ruby-lsp").expand_path(Dir.pwd) + "Gemfile"
        Object.any_instance.expects(:system).with(
          bundle_env(bundle_gemfile.to_s),
          "(bundle check || bundle install) 1>&2",
        ).returns(true)

        Bundler.with_unbundled_env do
          run_script
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
            run_script
          end
        end
      end
    end
  end

  def test_does_nothing_if_both_ruby_lsp_and_debug_are_gemspec_dependencies
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
          Object.any_instance.expects(:system).with(bundle_env, "(bundle check || bundle install) 1>&2").returns(true)
          Bundler::LockfileParser.any_instance.expects(:dependencies).returns({})
          run_script
        end

        refute_path_exists(".ruby-lsp")
      end
    end
  end

  def test_creates_custom_bundle_with_specified_branch
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        bundle_gemfile = Pathname.new(".ruby-lsp").expand_path(Dir.pwd) + "Gemfile"
        Object.any_instance.expects(:system).with(
          bundle_env(bundle_gemfile.to_s),
          "(bundle check || bundle install) 1>&2",
        ).returns(true)

        Bundler.with_unbundled_env do
          run_script(branch: "test-branch")
        end

        assert_path_exists(".ruby-lsp")
        assert_path_exists(".ruby-lsp/Gemfile")
        assert_match(%r{ruby-lsp.*github: "Shopify/ruby-lsp", branch: "test-branch"}, File.read(".ruby-lsp/Gemfile"))
        assert_match("debug", File.read(".ruby-lsp/Gemfile"))
      end
    end
  end

  def test_install_prerelease_versions_if_experimental_is_true
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
            run_script
          end
        end

        capture_subprocess_io do
          Object.any_instance.expects(:system).with(
            bundle_env(".ruby-lsp/Gemfile"),
            "((bundle check && bundle update ruby-lsp debug --pre) || bundle install) 1>&2",
          ).returns(true)

          Bundler.with_unbundled_env do
            run_script(experimental: true)
          end
        end
      end
    end
  end

  def test_returns_bundle_app_config_if_there_is_local_config
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        bundle_gemfile = Pathname.new(".ruby-lsp").expand_path(Dir.pwd) + "Gemfile"
        Bundler.with_unbundled_env do
          Bundler.settings.temporary(without: "production") do
            Object.any_instance.expects(:system).with(
              bundle_env(bundle_gemfile.to_s),
              "(bundle check || bundle install) 1>&2",
            ).returns(true)

            run_script
          end
        end
      end
    end
  end

  def test_custom_bundle_uses_alternative_gemfiles
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        File.write(File.join(dir, "gems.rb"), <<~GEMFILE)
          source "https://rubygems.org"
          gem "rdoc"
        GEMFILE

        Bundler.with_unbundled_env do
          capture_subprocess_io do
            system("bundle install")
            run_script
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

  def test_ensures_lockfile_remotes_are_relative_to_default_gemfile
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        # The structure used in Rails uncovered a bug in our custom bundle logic. Rails is an empty gem with a bunch of
        # nested gems. The lockfile includes remotes that use relative paths and we need to adjust those when we copy
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
            run_script
          end
        end

        assert_path_exists(".ruby-lsp")
        assert_path_exists(".ruby-lsp/Gemfile.lock")
        assert_match("remote: ..", File.read(".ruby-lsp/Gemfile.lock"))
      end
    end
  end

  def test_ruby_lsp_rails_is_automatically_included_in_rails_apps
    Dir.mktmpdir do |dir|
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

        Object.any_instance.expects(:system).with(
          bundle_env(".ruby-lsp/Gemfile"),
          "(bundle check || bundle install) 1>&2",
        ).returns(true)
        Bundler.with_unbundled_env do
          run_script
        end

        assert_path_exists(".ruby-lsp/Gemfile")
        assert_match('gem "ruby-lsp-rails"', File.read(".ruby-lsp/Gemfile"))
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

        # Write the custom bundle's lockfile using a fake version that doesn't exist to force bundle install to fail
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
          run_script
        end

        # Verify that the script recovered and re-generated the custom bundle from scratch
        assert_path_exists(".ruby-lsp/Gemfile")
        assert_path_exists(".ruby-lsp/Gemfile.lock")
        refute_match("999.1.555", File.read(".ruby-lsp/Gemfile.lock"))
      end
    end
  end

  private

  # This method runs the script and then immediately unloads it. This allows us to make assertions against the effects
  # of running the script multiple times
  def run_script(path = "/fake/project/path", expected_path: nil, **options)
    bundle_path = T.let(nil, T.nilable(String))

    stdout, _stderr = capture_subprocess_io do
      _bundle_gemfile, bundle_path = RubyLsp::SetupBundler.new(path, **options).setup!
    end

    assert_empty(stdout)
    assert_equal(expected_path, bundle_path) if expected_path
  end

  def bundle_env(bundle_gemfile = "Gemfile")
    bundle_gemfile_path = Pathname.new(bundle_gemfile)
    path = Bundler.settings["path"]

    env = {}
    env["BUNDLE_PATH"] = File.expand_path(path, Dir.pwd) if path
    env["BUNDLE_GEMFILE"] =
      bundle_gemfile_path.absolute? ? bundle_gemfile_path.to_s : bundle_gemfile_path.expand_path(Dir.pwd).to_s

    local_config_path = File.join(Dir.pwd, ".bundle")
    env["BUNDLE_APP_CONFIG"] = local_config_path if Dir.exist?(local_config_path)
    env
  end
end
