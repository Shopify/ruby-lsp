# typed: true
# frozen_string_literal: true

require "test_helper"

class IntegrationTest < Minitest::Test
  def test_ruby_lsp_doctor_works
    skip("CI only") unless ENV["CI"]

    in_isolation do
      system("bundle exec ruby-lsp --doctor")
      assert_equal(0, $CHILD_STATUS)
    end
  end

  def test_ruby_lsp_check_works
    skip("CI only") unless ENV["CI"]

    in_isolation do
      system("bundle exec ruby-lsp-check")
      assert_equal(0, $CHILD_STATUS)
    end
  end

  def test_adds_bundler_version_as_part_of_exec_command
    in_temp_dir do |dir|
      File.write(File.join(dir, "Gemfile"), <<~GEMFILE)
        source "https://rubygems.org"
        gem "ruby-lsp", path: "#{Bundler.root}"
      GEMFILE

      Bundler.with_unbundled_env do
        capture_subprocess_io do
          system("bundle install")

          Object.any_instance.expects(:exec).with do |env, command|
            env.key?("BUNDLE_GEMFILE") &&
              env.key?("BUNDLER_VERSION") &&
              /bundle _[\d\.]+_ exec ruby-lsp/.match?(command)
          end.once.raises(StandardError.new("stop"))

          # We raise intentionally to avoid continuing running the executable
          assert_raises(StandardError) do
            load(Gem.bin_path("ruby-lsp", "ruby-lsp"))
          end
        end
      end
    end
  end

  def test_avoids_bundler_version_if_local_bin_is_in_path
    in_temp_dir do |dir|
      File.write(File.join(dir, "Gemfile"), <<~GEMFILE)
        source "https://rubygems.org"
        gem "ruby-lsp", path: "#{Bundler.root}"
      GEMFILE

      FileUtils.mkdir(File.join(dir, "bin"))
      FileUtils.touch(File.join(dir, "bin", "bundle"))

      Bundler.with_unbundled_env do
        capture_subprocess_io do
          system("bundle install")

          Object.any_instance.expects(:exec).with do |env, command|
            env.key?("BUNDLE_GEMFILE") &&
              !env.key?("BUNDLER_VERSION") &&
              "bundle exec ruby-lsp" == command
          end.once.raises(StandardError.new("stop"))

          ENV["PATH"] = "./bin#{File::PATH_SEPARATOR}#{ENV["PATH"]}"
          # We raise intentionally to avoid continuing running the executable
          assert_raises(StandardError) do
            load(Gem.bin_path("ruby-lsp", "ruby-lsp"))
          end
        end
      end
    end
  end

  def test_launch_mode_with_no_gemfile
    skip("CI only") unless ENV["CI"]

    in_temp_dir do |dir|
      Bundler.with_unbundled_env do
        launch(dir)
      end
    end
  end

  def test_launch_mode_with_missing_lockfile
    skip("CI only") unless ENV["CI"]

    in_temp_dir do |dir|
      File.write(File.join(dir, "Gemfile"), <<~RUBY)
        source "https://rubygems.org"
        gem "stringio"
      RUBY

      Bundler.with_unbundled_env do
        launch(dir)
      end
    end
  end

  def test_launch_mode_with_full_bundle
    skip("CI only") unless ENV["CI"]

    in_temp_dir do |dir|
      File.write(File.join(dir, "Gemfile"), <<~RUBY)
        source "https://rubygems.org"
        gem "stringio"
      RUBY

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
        launch(dir)
      end
    end
  end

  def test_launch_mode_with_no_gemfile_and_bundle_path
    skip("CI only") unless ENV["CI"]

    in_temp_dir do |dir|
      Bundler.with_unbundled_env do
        system("bundle config --local path #{File.join("vendor", "bundle")}")
        assert_path_exists(File.join(dir, ".bundle", "config"))

        launch(dir)
      end
    end
  end

  private

  def launch(workspace_path)
    initialize_request = {
      id: 1,
      method: "initialize",
      params: {
        initializationOptions: {},
        capabilities: { general: { positionEncodings: ["utf-8"] } },
        workspaceFolders: [{ uri: URI::Generic.from_path(path: workspace_path).to_s }],
      },
    }.to_json

    $stdin.expects(:gets).with("\r\n\r\n").once.returns("Content-Length: #{initialize_request.bytesize}")
    $stdin.expects(:read).with(initialize_request.bytesize).once.returns(initialize_request)

    # Make `new` return a mock that raises so that we don't print to stdout and stop immediately after boot
    server_object = mock("server")
    server_object.expects(:start).once.raises(StandardError.new("stop"))
    RubyLsp::Server.expects(:new).returns(server_object)

    # We load the launcher binary in the same process as the tests are running. We cannot try to re-activate a different
    # Bundler version, because that throws an error
    if File.exist?(File.join(workspace_path, "Gemfile.lock"))
      spec_mock = mock("specification")
      spec_mock.expects(:activate).once
      Gem::Specification.expects(:find_by_name).with do |name, version|
        name == "bundler" && !version.empty?
      end.returns(spec_mock)
    end

    # Verify that we are setting up the bundle, but there's no actual need to do it
    Bundler.expects(:setup).once

    assert_raises(StandardError) do
      load(File.expand_path("../exe/ruby-lsp-launcher", __dir__))
    end

    assert_path_exists(File.join(workspace_path, ".ruby-lsp", "bundle_gemfile"))
  end

  def in_temp_dir
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        yield(dir)
      end
    end
  end

  def in_isolation(&block)
    gem_path = Bundler.root
    in_temp_dir do |dir|
      File.write(File.join(dir, "Gemfile"), <<~GEMFILE)
        source "https://rubygems.org"
        gem "ruby-lsp", path: "#{gem_path}"
      GEMFILE

      Bundler.with_unbundled_env do
        capture_subprocess_io do
          system("bundle install")

          # Only do this after `bundle install` as to not change the lockfile
          File.write(File.join(dir, "Gemfile"), <<~GEMFILE, mode: "a+")
            # This causes ruby-lsp to run in its own directory without
            # all the supplementary gems like rubocop
            Dir.chdir("#{gem_path}")
          GEMFILE

          yield
        end
      end
    end
  end
end
