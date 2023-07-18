# typed: true
# frozen_string_literal: true

require "test_helper"
require "ruby_lsp/setup_bundler"

class SetupBundlerTest < Minitest::Test
  def test_does_nothing_when_running_in_the_ruby_lsp
    Object.any_instance.expects(:system).with(bundle_install_command(update: false))
    run_script("/some/path/ruby-lsp")
    refute_path_exists(".ruby-lsp")
  end

  def test_does_nothing_if_both_ruby_lsp_and_debug_are_in_the_bundle
    Object.any_instance.expects(:system).with(bundle_install_command(update: false))
    Bundler::LockfileParser.any_instance.expects(:dependencies).returns({ "ruby-lsp" => true, "debug" => true })
    run_script
    refute_path_exists(".ruby-lsp")
  end

  def test_removes_ruby_lsp_folder_if_both_gems_were_added_to_the_bundle
    Object.any_instance.expects(:system).with(bundle_install_command(update: false))
    Bundler::LockfileParser.any_instance.expects(:dependencies).returns({ "ruby-lsp" => true, "debug" => true })
    FileUtils.mkdir(".ruby-lsp")
    run_script
    refute_path_exists(".ruby-lsp")
  ensure
    FileUtils.rm_r(".ruby-lsp") if Dir.exist?(".ruby-lsp")
  end

  def test_creates_custom_bundle
    Object.any_instance.expects(:system).with(bundle_install_command(".ruby-lsp/Gemfile"))
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
    Object.any_instance.expects(:system).with(bundle_install_command(".ruby-lsp/Gemfile"))
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

  def test_does_not_copy_gemfile_lock_when_not_modified
    Object.any_instance.expects(:system).with(bundle_install_command(".ruby-lsp/Gemfile"))
    Bundler::LockfileParser.any_instance.expects(:dependencies).returns({})
    FileUtils.mkdir(".ruby-lsp")
    FileUtils.cp("Gemfile.lock", ".ruby-lsp/Gemfile.lock")

    run_script
  ensure
    FileUtils.rm_r(".ruby-lsp")
  end

  def test_uses_absolute_bundle_path_for_bundle_install
    Bundler.settings.set_global("path", "vendor/bundle")
    Object.any_instance.expects(:system).with(bundle_install_command(".ruby-lsp/Gemfile"))
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
  def run_script(path = "/fake/project/path")
    RubyLsp::SetupBundler.new(path).setup!
  end

  def bundle_install_command(bundle_gemfile = nil, update: true)
    path = Bundler.settings["path"]

    command = +""
    command << "BUNDLE_PATH=#{File.expand_path(path, Dir.pwd)} " if path
    command << "BUNDLE_GEMFILE=#{bundle_gemfile} " if bundle_gemfile
    command << if update
      "bundle update ruby-lsp debug "
    else
      "bundle install "
    end
    command << "1>&2"
  end
end
