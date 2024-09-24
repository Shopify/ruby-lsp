# typed: true
# frozen_string_literal: true

require "test_helper"

class IntegrationTest < Minitest::Test
  def setup
    skip("CI only") unless ENV["CI"]
  end

  def test_ruby_lsp_doctor_works
    in_isolation do
      system("bundle exec ruby-lsp --doctor")
      assert_equal(0, $CHILD_STATUS)
    end
  end

  def test_ruby_lsp_check_works
    in_isolation do
      system("bundle exec ruby-lsp-check")
      assert_equal(0, $CHILD_STATUS)
    end
  end

  private

  def in_isolation(&block)
    gem_path = Bundler.root
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
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
end
