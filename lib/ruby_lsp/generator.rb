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
        puts "Inside existing project. Creating add-on files..."
        create_addon_files
      else
        puts "Not inside existing project. Prompting to create new gem..."
        create_new_gem
      end
    end

    private

    sig { returns(T::Boolean) }
    def inside_existing_project?
      File.exist?("Gemfile")
    end

    sig { params(string: String).returns(String) }
    def camelize(string)
      return string if string == "ruby-lsp"

      string
        .gsub("ruby-lsp-", "")
        .split(/[-_]/)
        .map(&:capitalize)
        .join
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

          RubyLsp::Addon.depend_on_ruby_lsp!(">= 0.23.1", "< 0.24")

          module RubyLsp
            module #{camelize(addon_name)}
              class Addon < ::RubyLsp::Addon
                # Performs any activation that needs to happen once when the language server is booted
                def activate(global_state, message_queue)
                  # Add your logic here
                end

                # Performs any cleanup when shutting down the server, like terminating a subprocess
                def deactivate
                  # Add your logic here
                end

                # Returns the name of the add-on
                def name
                  "Ruby LSP My Gem"
                end

                # Defining a version for the add-on is mandatory. This version doesn't necessarily need to match the version of
                # the gem it belongs to
                def version
                  "0.1.0"
                end
              end
            end
          end
        RUBY
      )

      create_test_file

      puts "Add-on '#{addon_name}' created successfully! Please follow guidelines on https://shopify.github.io/ruby-lsp/add-ons.html"
    end

    sig { void }
    def create_new_gem
      addon_name = T.must(@addon_name)
      system("bundle gem #{addon_name}")
      add_ruby_lsp_to_gemfile
      Dir.chdir(addon_name) do
        create_addon_files
      end
    end

    sig { void }
    def add_ruby_lsp_to_gemfile
      gemfile_path = "Gemfile"

      unless File.exist?(gemfile_path)
        puts "Gemfile not found. Please ensure you are in the root directory of your gem."
        return
      end

      gemfile_content = File.read(gemfile_path)

      if gemfile_content.include?("gem 'ruby-lsp'") || gemfile_content.include?('gem "ruby-lsp"')
        puts "ruby-lsp is already in the Gemfile."
        return
      end

      updated_content = gemfile_content + "\ngem \"ruby-lsp\", \">= 0.23.1\", group: :development\n"

      File.write(gemfile_path, updated_content)

      puts "Added ruby-lsp as a development dependency to the Gemfile."
    end

    sig { returns(Symbol) }
    def check_test_framework
      if File.exist?("Gemfile")
        gemfile_content = T.let(File.read("Gemfile"), String)
        if gemfile_content.include?("rspec")
          :rspec
        elsif gemfile_content.include?("minitest")
          :minitest
        elsif gemfile_content.include?("test-unit")
          :test_unit
        else
          :minitest
        end
      else
        :minitest
      end
    end

    sig { void }
    def create_test_file
      addon_name = T.must(@addon_name)
      test_dir = "test/ruby_lsp/#{@addon_name}"
      spec_test_dir = "spec/ruby_lsp/#{@addon_name}"
      test_framework = check_test_framework

      case test_framework
      when :rspec
        FileUtils.mkdir_p(spec_test_dir)
        File.write("#{spec_test_dir}/addon_spec.rb", <<~RUBY)
          # frozen_string_literal: true

          require "spec_helper"

          RSpec.describe RubyLsp::#{camelize(addon_name)}::Addon do
            it "does something useful" do
              expect(true).to eq(true)
            end
          end
        RUBY
      when :minitest
        FileUtils.mkdir_p(test_dir)
        File.write("#{test_dir}/addon_test.rb", <<~RUBY)
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
      when :test_unit
        FileUtils.mkdir_p(test_dir)
        File.write("#{test_dir}/addon_test.rb", <<~RUBY)
          # frozen_string_literal: true

          require "test_helper"

          class AddonTest < Test::Unit::TestCase
            def test_example
              assert true
            end
          end
        RUBY
      else
        raise "Unsupported test framework: #{test_framework}"
      end
    end
  end
end
