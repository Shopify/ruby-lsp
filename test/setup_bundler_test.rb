# typed: true
# frozen_string_literal: true

require "test_helper"
require "ruby_lsp/setup_bundler"

class SetupBundlerTest < Minitest::Test
  def test_does_nothing_if_both_ruby_lsp_and_debug_are_in_the_bundle
    Object.any_instance.expects(:system).with(bundle_env, "bundle install 1>&2")
    Bundler::LockfileParser.any_instance.expects(:dependencies).returns({ "ruby-lsp" => true, "debug" => true })
    run_script
    refute_path_exists(".ruby-lsp")
  end

  def test_removes_ruby_lsp_folder_if_both_gems_were_added_to_the_bundle
    Object.any_instance.expects(:system).with(bundle_env, "bundle install 1>&2")
    Bundler::LockfileParser.any_instance.expects(:dependencies).returns({ "ruby-lsp" => true, "debug" => true })
    FileUtils.mkdir(".ruby-lsp")
    run_script
    refute_path_exists(".ruby-lsp")
  ensure
    FileUtils.rm_r(".ruby-lsp") if Dir.exist?(".ruby-lsp")
  end

  def test_creates_custom_bundle
    Object.any_instance.expects(:system).with(bundle_env(".ruby-lsp/Gemfile"), "bundle install 1>&2")
    Bundler::LockfileParser.any_instance.expects(:dependencies).returns({}).at_least_once
    run_script

    assert_path_exists(".ruby-lsp")
    assert_path_exists(".ruby-lsp/Gemfile")
    assert_path_exists(".ruby-lsp/Gemfile.lock")
    assert_match("ruby-lsp", File.read(".ruby-lsp/Gemfile"))
    assert_match("debug", File.read(".ruby-lsp/Gemfile"))
  ensure
    FileUtils.rm_r(".ruby-lsp")
  end

  def test_copies_gemfile_lock_when_modified
    Object.any_instance.expects(:system).with(bundle_env(".ruby-lsp/Gemfile"), "bundle install 1>&2")
    Bundler::LockfileParser.any_instance.expects(:dependencies).returns({}).twice
    FileUtils.mkdir(".ruby-lsp")
    FileUtils.touch(".ruby-lsp/Gemfile.lock")
    # Wait a little bit so that the modified timestamps don't match
    sleep(0.05)
    FileUtils.touch("Gemfile.lock")

    FileUtils.expects(:cp).with(
      File.expand_path("Gemfile.lock", Dir.pwd),
      File.expand_path(".ruby-lsp/Gemfile.lock", Dir.pwd),
    )

    run_script
  ensure
    FileUtils.rm_r(".ruby-lsp")
  end

  def test_loading_custom_bundle_dependencies_is_lazy
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

        # Update the modified timestamp for the lockfile
        sleep(0.05)
        FileUtils.touch("Gemfile.lock")

        # At this point, the custom bundle includes the `ruby-lsp` in its lockfile, but that will be overwritten when we
        # copy the top level lockfile. If custom bundle dependencies are eagerly evaluated, then we would think the
        # ruby-lsp is a part of the custom lockfile and would try to run `bundle update ruby-lsp`, which would fail. If
        # we evaluate lazily, then we only find dependencies after the lockfile was copied, and then run bundle install
        # instead, which re-locks and adds the ruby-lsp
        Object.any_instance.expects(:system).with(bundle_env(".ruby-lsp/Gemfile"), "bundle install 1>&2")
        Bundler.with_unbundled_env do
          run_script
        end
      end
    end
  end

  def test_does_not_copy_gemfile_lock_when_not_modified
    Object.any_instance.expects(:system).with(bundle_env(".ruby-lsp/Gemfile"), "bundle install 1>&2")
    Bundler::LockfileParser.any_instance.expects(:dependencies).returns({}).twice
    FileUtils.mkdir(".ruby-lsp")
    FileUtils.cp("Gemfile.lock", ".ruby-lsp/Gemfile.lock")

    run_script
  ensure
    FileUtils.rm_r(".ruby-lsp")
  end

  def test_uses_absolute_bundle_path_for_bundle_install
    Bundler.settings.set_global("path", "vendor/bundle")
    Object.any_instance.expects(:system).with(bundle_env(".ruby-lsp/Gemfile"), "bundle install 1>&2")
    Bundler::LockfileParser.any_instance.expects(:dependencies).returns({}).at_least_once
    run_script
  ensure
    # We need to revert the changes to the bundler config or else this actually changes ~/.bundle/config
    Bundler.settings.set_global("path", nil)
    FileUtils.rm_r(".ruby-lsp")
  end

  def test_creates_custom_bundle_if_no_gemfile
    # Create a temporary directory with no Gemfile or Gemfile.lock
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        bundle_gemfile = Pathname.new(".ruby-lsp").expand_path(Dir.pwd) + "Gemfile"
        Object.any_instance.expects(:system).with(bundle_env(bundle_gemfile.to_s), "bundle install 1>&2")

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
          Object.any_instance.expects(:system).with(bundle_env, "bundle install 1>&2")
          Bundler::LockfileParser.any_instance.expects(:dependencies).returns({})
          run_script
        end

        refute_path_exists(".ruby-lsp")
      end
    end
  end

  private

  # This method runs the script and then immediately unloads it. This allows us to make assertions against the effects
  # of running the script multiple times
  def run_script(path = "/fake/project/path")
    RubyLsp::SetupBundler.new(path).setup!
  end

  def bundle_env(bundle_gemfile = "Gemfile")
    bundle_gemfile_path = Pathname.new(bundle_gemfile)
    path = Bundler.settings["path"]

    env = {}
    env["BUNDLE_PATH"] = File.expand_path(path, Dir.pwd) if path
    env["BUNDLE_GEMFILE"] =
      bundle_gemfile_path.absolute? ? bundle_gemfile_path.to_s : bundle_gemfile_path.expand_path(Dir.pwd).to_s
    env
  end
end
