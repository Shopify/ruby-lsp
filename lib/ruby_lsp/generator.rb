# typed: strict
# frozen_string_literal: true

module RubyLsp
  class Generator
    extend T::Sig

    sig { params(addon_name: T.nilable(String)).void }
    def initialize(addon_name)
      @addon_name = T.let(addon_name, T.nilable(String))
    end

    sig { void }
    def run
      if inside_existing_project?
        create_addon_files
      else
        create_new_gem
      end
    end

    private

    sig { returns(T::Boolean) }
    def inside_existing_project?
      File.exist?("Gemfile")
    end

    sig { void }
    def create_addon_files
      addon_name = T.must(@addon_name)
      addon_dir = T.let("lib/ruby_lsp/#{addon_name}", String)
      FileUtils.mkdir_p(addon_dir)

      # Create addon.rb
      File.write(
        "#{addon_dir}/addon.rb",
        <<~RUBY,
          # frozen_string_literal: true

          module RubyLsp
            module #{camelize(addon_name)}
              class Addon

                # Your add-on logic here
              end
            end
          end
        RUBY
      )

      # Create a test file
      test_dir = T.let("test/ruby_lsp/#{addon_name}", String)
      FileUtils.mkdir_p(test_dir)
      File.write(
        "#{test_dir}/addon_test.rb",
        <<~RUBY,
          # frozen_string_literal: true

          require "test_helper"

          module RubyLsp
            module #{camelize(addon_name)}
              class AddonTest < Minitest::Test

                def test_example
                  assert true
                end
              end
            end
          end
        RUBY
      )

      puts "Add-on '#{addon_name}' created successfully!"
    end

    sig { void }
    def create_new_gem
      addon_name = T.must(@addon_name)
      system("bundle gem #{addon_name}")
      Dir.chdir(addon_name) do
        create_addon_files
      end
    end

    sig { params(string: String).returns(String) }
    def camelize(string)
      string.split("_").map(&:capitalize).join
    end
  end
end
