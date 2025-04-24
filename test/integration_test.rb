# typed: true
# frozen_string_literal: true

require "test_helper"

class IntegrationTest < Minitest::Test
  def setup
    @root = Bundler.root
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
    ENV["PS1"] = "\xE2\x96\xB7".b

    _stdout, stderr, status = Open3.capture3(
      "ruby",
      "-EUTF-8:UTF-8",
      File.join(__dir__, "..", "vscode", "activation.rb"),
    )

    assert_equal(0, status.exitstatus, stderr)

    match = /RUBY_LSP_ACTIVATION_SEPARATOR(.*)RUBY_LSP_ACTIVATION_SEPARATOR/m.match(stderr) #: as !nil
    activation_string = match[1] #: as !nil
    version, gem_path, yjit, *fields = activation_string.split("RUBY_LSP_FS")

    assert_equal(RUBY_VERSION, version)
    refute_nil(gem_path)
    assert(yjit)

    assert_includes(fields, "PS1RUBY_LSP_VS#{ENV["PS1"]}")

    fields.each do |field|
      key, value = field.split("RUBY_LSP_VS")
      refute_equal(key.encoding, Encoding::BINARY) if key
      refute_equal(value.encoding, Encoding::BINARY) if value
    end
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
        capture_subprocess_io do
          system("bundle install")
        end
      end

      Bundler.with_unbundled_env do
        launch(dir, "ruby-lsp")
      end

      assert_match(/BUNDLED WITH\n\s*2.5.7/, File.read(File.join(dir, ".ruby-lsp", "Gemfile.lock")))
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

      assert_match(/BUNDLED WITH\n\s*2.5.7/, File.read(File.join(dir, ".ruby-lsp", "Gemfile.lock")))
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
    in_temp_dir do |dir|
      Bundler.with_unbundled_env do
        system("bundle config --local path #{File.join("vendor", "bundle")}")
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

  private

  def launch(workspace_path, exec = "ruby-lsp-launcher", extra_env = {})
    specification = Gem::Specification.find_by_name("ruby-lsp")
    paths = [specification.full_gem_path]
    paths.concat(specification.dependencies.map { |dep| dep.to_spec.full_gem_path })

    load_path = $LOAD_PATH.filter_map do |path|
      next unless paths.any? { |gem_path| path.start_with?(gem_path) } || !path.start_with?(Bundler.bundle_path.to_s)

      ["-I", File.expand_path(path)]
    end.uniq.flatten

    stdin, stdout, stderr, wait_thr = Open3 #: as untyped
      .popen3(
        extra_env,
        Gem.ruby,
        *load_path,
        File.join(@root, "exe", exec),
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
    read_message(stdout)
    # Verify that initialization didn't fail
    initialize_response = read_message(stdout)
    refute(initialize_response[:error], initialize_response.dig(:error, :message))

    send_message(stdin, { id: 2, method: "shutdown" })
    send_message(stdin, { method: "exit" })

    # Wait until the process exits
    wait_thr.join

    # If the child process failed, it is really difficult to diagnose what's happening unless we read what was printed
    # to stderr
    unless wait_thr.value.success?
      require "timeout"

      Timeout.timeout(5) do
        flunk("Process failed\n#{stderr.read}")
      end
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

  def read_message(stdout)
    headers = stdout.gets("\r\n\r\n")
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
