# typed: true
# frozen_string_literal: true

require "test_helper"

class SetupBundlerTest < Minitest::Test
  def test_does_nothing_when_running_in_the_ruby_lsp
    run_script
    refute_path_exists(".ruby-lsp")
  end

  def test_does_nothing_if_both_ruby_lsp_and_debug_are_in_the_bundle
    Bundler::LockfileParser.any_instance.expects(:dependencies).returns({ "ruby-lsp" => true, "debug" => true })
    run_script
    refute_path_exists(".ruby-lsp")
  end

  def test_creates_custom_bundle
    Object.any_instance.expects(:system).with(bundle_install_command)
    Bundler::LockfileParser.any_instance.expects(:dependencies).returns({})
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
    Object.any_instance.expects(:system).with(bundle_install_command)
    Bundler::LockfileParser.any_instance.expects(:dependencies).returns({})
    FileUtils.mkdir(".ruby-lsp")
    FileUtils.touch(".ruby-lsp/Gemfile.lock")
    # Wait a little bit so that the modified timestamps don't match
    sleep(0.05)
    FileUtils.touch("Gemfile.lock")

    FileUtils.expects(:cp).with("Gemfile.lock", ".ruby-lsp/Gemfile.lock")

    run_script
  ensure
    FileUtils.rm_r(".ruby-lsp")
  end

  def test_uses_absolute_bundle_path_for_bundle_install
    Bundler.settings.set_global("path", "vendor/bundle")
    Object.any_instance.expects(:system).with(bundle_install_command)
    Bundler::LockfileParser.any_instance.expects(:dependencies).returns({})
    run_script
  ensure
    # We need to revert the changes to the bundler config or else this actually changes ~/.bundle/config
    Bundler.settings.set_global("path", nil)
    FileUtils.rm_r(".ruby-lsp")
  end

  private

  # This method runs the script and then immediately unloads it. This allows us to make assertions against the effects
  # of running the script multiple times
  def run_script
    path = File.expand_path("../lib/ruby_lsp/setup_bundler.rb", __dir__)
    require path
  ensure
    $LOADED_FEATURES.delete(path)
  end

  def bundle_install_command
    path = Bundler.settings["path"]

    command = +""
    command << "BUNDLE_PATH=#{File.expand_path(path, Dir.pwd)} " if path
    command << "BUNDLE_GEMFILE=.ruby-lsp/Gemfile bundle install "
    command << "1>&2"
  end
end
