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

  private

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
