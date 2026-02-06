# typed: true
# frozen_string_literal: true

require "test_helper"
require "timeout"

class IntegrationTest < Minitest::Test
  def setup
    @bundle_path = Bundler.bundle_path.to_s
  end

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

  def test_activation_script_succeeds_even_on_binary_encoding
    ENV["LC_ALL"] = "C"
    ENV["LANG"] = "C"
    ENV["NOT_VALID"] = "\xE2\x96\xB7".b

    _stdout, stderr, status = Open3.capture3(
      "ruby",
      "-EUTF-8:UTF-8",
      File.join(__dir__, "..", "vscode", "activation.rb"),
    )

    assert_equal(0, status.exitstatus, stderr)
    stderr.force_encoding(Encoding::UTF_8)

    match = /RUBY_LSP_ACTIVATION_SEPARATOR(.*)RUBY_LSP_ACTIVATION_SEPARATOR/m.match(stderr) #: as !nil
    activation_string = match[1] #: as !nil
    version, gem_path, yjit, *fields = activation_string.split("RUBY_LSP_FS")

    assert_equal(RUBY_VERSION, version)
    refute_nil(gem_path)
    assert(yjit)

    assert(fields.find { |f| f.start_with?("NOT_VALIDRUBY_LSP_VS") })

    fields.each do |field|
      key, value = field.split("RUBY_LSP_VS")
      refute_equal(key.encoding, Encoding::BINARY) if key
      refute_equal(value.encoding, Encoding::BINARY) if value
    end
  end

  def test_chruby_activation_script
    _stdout, stderr, status = Open3.capture3(
      "ruby",
      "-EUTF-8:UTF-8",
      File.join(__dir__, "..", "vscode", "chruby_activation.rb"),
      RUBY_VERSION,
    )

    assert_equal(0, status.exitstatus, stderr)

    default_gems, gem_home, yjit, version = stderr.split("RUBY_LSP_ACTIVATION_SEPARATOR")

    assert_equal(RUBY_VERSION, version)
    # These may be switched in CI due to Bundler settings, so we use simpler assertions
    assert(yjit)
    assert(gem_home)
    assert(default_gems)
  end

  def test_activation_script_succeeds_on_invalid_unicode
    ENV["LC_ALL"] = "C"
    ENV["LANG"] = "C"
    ENV["INVALID_UTF8"] = "\xE2\x80".b

    _stdout, stderr, status = Open3.capture3(
      "ruby",
      "-EUTF-8:UTF-8",
      File.join(__dir__, "..", "vscode", "activation.rb"),
    )

    assert_equal(0, status.exitstatus, stderr)
    stderr.force_encoding(Encoding::UTF_8)

    match = /RUBY_LSP_ACTIVATION_SEPARATOR(.*)RUBY_LSP_ACTIVATION_SEPARATOR/m.match(stderr) #: as !nil
    activation_string = match[1] #: as !nil
    version, gem_path, yjit, *fields = activation_string.split("RUBY_LSP_FS")

    assert_equal(RUBY_VERSION, version)
    refute_nil(gem_path)
    assert(yjit)

    fields.each do |field|
      key, value = field.split("RUBY_LSP_VS")
      refute_equal(key.encoding, Encoding::BINARY) if key
      refute_equal(value.encoding, Encoding::BINARY) if value
    end
  end

  def test_uses_same_bundler_version_as_main_app
    in_temp_dir do |dir|
      File.write(File.join(dir, "Gemfile"), <<~RUBY)
        source "https://rubygems.org"
        gem "stringio"
      RUBY

      lockfile_contents = <<~LOCKFILE
        GEM
          remote: https://rubygems.org/
          specs:
            stringio (3.1.7)

        PLATFORMS
          arm64-darwin-23
          ruby

        DEPENDENCIES
          stringio

        BUNDLED WITH
          4.0.2
      LOCKFILE
      File.write(File.join(dir, "Gemfile.lock"), lockfile_contents)

      Bundler.with_unbundled_env do
        capture_subprocess_io do
          system("bundle install")
        end
      end

      Bundler.with_unbundled_env do
        launch(dir, "ruby-lsp")
      end

      assert_match(/BUNDLED WITH\n\s*4.0.2/, File.read(File.join(dir, ".ruby-lsp", "Gemfile.lock")))
    end
  end

  def test_does_not_use_custom_binstubs_if_they_are_in_the_path
    in_temp_dir do |dir|
      File.write(File.join(dir, "Gemfile"), <<~RUBY)
        source "https://rubygems.org"
        gem "stringio"
      RUBY

      lockfile_contents = <<~LOCKFILE
        GEM
          remote: https://rubygems.org/
          specs:
            stringio (3.1.7)

        PLATFORMS
          arm64-darwin-23
          ruby

        DEPENDENCIES
          stringio

        BUNDLED WITH
          4.0.2
      LOCKFILE
      File.write(File.join(dir, "Gemfile.lock"), lockfile_contents)

      Bundler.with_unbundled_env do
        capture_subprocess_io do
          system("bundle install")
        end
      end

      bin_path = File.join(dir, "bin")
      FileUtils.mkdir(bin_path)
      File.write(File.join(bin_path, "bundle"), <<~RUBY)
        #!/usr/bin/env ruby
        raise "This should not be called"
      RUBY
      FileUtils.chmod(0o755, File.join(bin_path, "bundle"))

      Bundler.with_unbundled_env do
        launch(dir, "ruby-lsp", { "PATH" => "#{bin_path}#{File::PATH_SEPARATOR}#{ENV["PATH"]}" })
      end

      assert_match(/BUNDLED WITH\n\s*4.0.2/, File.read(File.join(dir, ".ruby-lsp", "Gemfile.lock")))
    end
  end

  def test_launch_mode_with_no_gemfile
    in_temp_dir do |dir|
      Bundler.with_unbundled_env do
        launch(dir)
      end
    end
  end

  def test_launch_mode_with_missing_lockfile
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
    in_temp_dir do |dir|
      File.write(File.join(dir, "Gemfile"), <<~RUBY)
        source "https://rubygems.org"
        gem "stringio"
      RUBY

      lockfile_contents = <<~LOCKFILE
        GEM
          remote: https://rubygems.org/
          specs:
            stringio (3.2.0)

        PLATFORMS
          arm64-darwin-23
          ruby

        DEPENDENCIES
          stringio

        BUNDLED WITH
          4.0.2
      LOCKFILE
      File.write(File.join(dir, "Gemfile.lock"), lockfile_contents)

      Bundler.with_unbundled_env do
        launch(dir)
      end
    end
  end

  def test_launch_mode_with_no_gemfile_and_bundle_path
    in_temp_dir do |dir|
      Bundler.with_unbundled_env do
        system("bundle", "config", "set", "--local", "path", File.join("vendor", "bundle"))
        assert_path_exists(File.join(dir, ".bundle", "config"))
        launch(dir)
      end
    end
  end

  def test_composed_bundle_includes_debug
    in_temp_dir do |dir|
      Bundler.with_unbundled_env do
        launch(dir)

        _stdout, stderr = capture_subprocess_io do
          system(
            { "BUNDLE_GEMFILE" => File.join(dir, ".ruby-lsp", "Gemfile") },
            "bundle exec ruby -e 'require \"debug\"'",
          )
        end
        refute_match(/cannot load such file/, stderr)
      end
    end
  end

  def test_launch_mode_with_bundle_package
    in_temp_dir do |dir|
      File.write(File.join(dir, "Gemfile"), <<~RUBY)
        source "https://rubygems.org"
        gem "stringio"
      RUBY

      Bundler.with_unbundled_env do
        capture_subprocess_io do
          system("bundle", "install")
          system("bundle", "package")
        end

        cached_gems = Dir.glob("#{dir}/vendor/cache/*.gem")
        refute_empty(cached_gems)

        launch(dir)
        assert_empty(Dir.glob("#{dir}/vendor/cache/*.gem") - cached_gems)
      end
    end
  end

  def test_launch_mode_update_does_not_modify_main_lockfile
    in_temp_dir do |dir|
      File.write(File.join(dir, "Gemfile"), <<~RUBY)
        source "https://rubygems.org"
        gem "ruby-lsp-rails"
        gem "debug"
      RUBY

      platforms = [
        "arm64-darwin-23",
        "ruby",
      ]
      platforms << "x64-mingw-ucrt" if Gem.win_platform?

      lockfile_contents = <<~LOCKFILE
        GEM
          remote: https://rubygems.org/
          specs:
            date (3.5.0)
            debug (1.11.0)
              irb (~> 1.10)
              reline (>= 0.3.8)
            erb (5.1.3)
            io-console (0.8.1)
            irb (1.15.3)
              pp (>= 0.6.0)
              rdoc (>= 4.0.0)
              reline (>= 0.4.2)
            language_server-protocol (3.17.0.5)
            logger (1.7.0)
            pp (0.6.3)
              prettyprint
            prettyprint (0.2.0)
            prism (1.6.0)
            psych (5.2.6)
              date
              stringio
            rbs (3.9.5)
              logger
            rdoc (6.15.1)
              erb
              psych (>= 4.0.0)
              tsort
            reline (0.6.3)
              io-console (~> 0.5)
            ruby-lsp (0.26.1)
              language_server-protocol (~> 3.17.0)
              prism (>= 1.2, < 2.0)
              rbs (>= 3, < 5)
            ruby-lsp-rails (0.4.8)
              ruby-lsp (>= 0.26.0, < 0.27.0)
            stringio (3.1.8)
            tsort (0.2.0)

        PLATFORMS
          #{platforms.join("\n  ")}

        DEPENDENCIES
          debug
          ruby-lsp-rails

        BUNDLED WITH
           4.0.2
      LOCKFILE
      File.write(File.join(dir, "Gemfile.lock"), lockfile_contents)

      Bundler.with_unbundled_env do
        capture_subprocess_io do
          system("bundle", "install")
        end

        # First launch creates the composed bundle
        launch(dir)

        # Second launch updates
        FileUtils.touch(File.join(dir, ".ruby-lsp", "needs_update"))
        launch(dir)
        assert_equal(lockfile_contents, File.read(File.join(dir, "Gemfile.lock")))
      end
    end
  end

  def test_launch_mode_retries_if_setup_failed_after_successful_install
    in_temp_dir do |dir|
      File.write(File.join(dir, "Gemfile"), <<~RUBY)
        source "https://rubygems.org"
        gem "rails", "8.1.1"
      RUBY

      Bundler.with_unbundled_env do
        # Generate a lockfile first
        capture_subprocess_io { system("bundle", "install") }
        # Uninstall the gem so that composing the bundle has to install it
        system("gem", "uninstall", "rails", "-v", "8.1.1", "--executables", "--silent")

        # Preemptively create the bundle_env file and acquire an exclusive lock on it, so that composing the bundle will
        # have to pause immediately after bundle installing, but before invoking Bundler.setup
        bundle_env_path = File.join(dir, ".ruby-lsp", "bundle_env")
        FileUtils.mkdir_p(File.dirname(bundle_env_path))
        FileUtils.touch(bundle_env_path)

        thread = Thread.new do
          File.open(bundle_env_path) do |f|
            f.flock(File::LOCK_EX)

            # Give the bundle compose enough time to finish and get stuck on the lock
            sleep(2)
            # Uninstall Rails after successfully bundle installing and before invoking Bundler.setup, which will cause
            # it to fail with `Bundler::GemNotFound`. This triggers our retry mechanism
            system("gem", "uninstall", "rails", "-v", "8.1.1", "--executables", "--silent")
          end
        end

        launch(dir)
        thread.join
      end
    end
  end

  def test_launching_an_older_server_version
    in_temp_dir do |dir|
      File.write(File.join(dir, "Gemfile"), <<~RUBY)
        source "https://rubygems.org"
        gem "ruby-lsp", "0.24.0"
      RUBY

      Bundler.with_unbundled_env do
        capture_subprocess_io do
          system("bundle", "install")
        end

        launch(dir)
      end
    end
  end

  private

  def launch(workspace_path, exec = "ruby-lsp-launcher", extra_env = {})
    stdin = nil #: IO?
    stdout = nil #: IO?
    stderr = nil #: IO?

    begin
      Timeout.timeout(180) do
        stdin, stdout, stderr, wait_thr = Open3 #: as untyped
          .popen3(
            extra_env,
            Gem.ruby,
            File.join(__dir__, "..", "exe", exec),
          )
        stdin.sync = true
        stdin.binmode
        stdout.sync = true
        stdout.binmode
        stderr.sync = true
        stderr.binmode

        send_message(stdin, {
          id: 1,
          method: "initialize",
          params: {
            initializationOptions: {},
            capabilities: { general: { positionEncodings: ["utf-8"] } },
            workspaceFolders: [{ uri: URI::Generic.from_path(path: workspace_path).to_s }],
          },
        })

        # First message is the log of initializing Ruby LSP
        read_message(stdout, stderr)
        # Verify that initialization didn't fail
        initialize_response = read_message(stdout, stderr)
        refute(initialize_response[:error], initialize_response.dig(:error, :message))

        send_message(stdin, { id: 2, method: "shutdown" })
        send_message(stdin, { method: "exit" })

        # Wait until the process exits
        wait_thr.join
      end
    rescue Timeout::Error
      if stderr
        Timeout.timeout(5) { flunk("Launching the server timed out\n#{stderr.read}") }
      end

      if stdout
        Timeout.timeout(5) { flunk("Launching the server timed out\n#{stdout.read}") }
      end
    ensure
      stdin&.close
      stdout&.close
      stderr&.close
    end

    assert_path_exists(File.join(workspace_path, ".ruby-lsp", "Gemfile"))
    assert_path_exists(File.join(workspace_path, ".ruby-lsp", "Gemfile.lock"))
    refute_path_exists(File.join(workspace_path, ".ruby-lsp", "install_error"))
  end

  def send_message(stdin, message)
    json_message = message.to_json
    stdin.write("Content-Length: #{json_message.bytesize}\r\n\r\n#{json_message}")
    stdin.flush
  end

  def read_message(stdout, stderr)
    headers = stdout.gets("\r\n\r\n")
    flunk(stderr.read) unless headers

    length = headers[/Content-Length: (\d+)/i, 1].to_i
    JSON.parse(stdout.read(length), symbolize_names: true)
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
