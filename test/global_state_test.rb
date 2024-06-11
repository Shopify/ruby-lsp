# typed: true
# frozen_string_literal: true

require "test_helper"

module RubyLsp
  class GlobalStateTest < Minitest::Test
    def test_detects_no_test_library_when_there_are_no_dependencies
      stub_direct_dependencies({})

      state = GlobalState.new
      state.apply_options({})
      assert_equal("unknown", state.test_library)
    end

    def test_detects_minitest
      stub_direct_dependencies("minitest" => "1.2.3")

      state = GlobalState.new
      state.apply_options({})
      assert_equal("minitest", state.test_library)
    end

    def test_does_not_detect_minitest_related_gems_as_minitest
      stub_direct_dependencies("minitest-reporters" => "1.2.3")

      state = GlobalState.new
      state.apply_options({})
      assert_equal("unknown", state.test_library)
    end

    def test_detects_test_unit
      stub_direct_dependencies("test-unit" => "1.2.3")

      state = GlobalState.new
      state.apply_options({})
      assert_equal("test-unit", state.test_library)
    end

    def test_detects_rails_if_minitest_is_present_and_bin_rails_exists
      stub_direct_dependencies("minitest" => "1.2.3")

      state = GlobalState.new
      state.stubs(:bin_rails_present).returns(true)
      state.apply_options({})
      assert_equal("rails", state.test_library)
    end

    def test_detects_rspec_if_both_rails_and_rspec_are_present
      stub_direct_dependencies("rspec" => "1.2.3")

      state = GlobalState.new
      state.apply_options({})
      assert_equal("rspec", state.test_library)
    end

    def test_apply_option_selects_formatter
      state = GlobalState.new
      state.apply_options({ initializationOptions: { formatter: "syntax_tree" } })
      assert_equal("syntax_tree", state.formatter)
    end

    def test_applying_auto_formatter_invokes_detection
      state = GlobalState.new
      state.apply_options({ initializationOptions: { formatter: "auto" } })
      assert_equal("rubocop", state.formatter)
    end

    def test_applying_auto_formatter_with_rubocop_extension
      state = GlobalState.new
      stub_direct_dependencies("rubocop-rails" => "1.2.3")
      state.apply_options({ initializationOptions: { formatter: "auto" } })
      assert_equal("rubocop", state.formatter)
    end

    def test_applying_auto_formatter_with_rubocop_as_transitive_dependency
      state = GlobalState.new

      stub_direct_dependencies("gem_with_config" => "1.2.3")
      stub_all_dependencies("gem_with_config", "rubocop")
      state.stubs(:dot_rubocop_yml_present).returns(true)

      state.apply_options({ initializationOptions: { formatter: "auto" } })

      assert_equal("rubocop", state.formatter)
    end

    def test_applying_auto_formatter_with_rubocop_as_transitive_dependency_without_config
      state = GlobalState.new

      stub_direct_dependencies("gem_with_config" => "1.2.3")
      stub_all_dependencies("gem_with_config", "rubocop")
      state.stubs(:dot_rubocop_yml_present).returns(false)

      state.apply_options({ initializationOptions: { formatter: "auto" } })

      assert_equal("none", state.formatter)
    end

    def test_applying_auto_formatter_with_rubocop_as_transitive_dependency_and_sytax_tree
      state = GlobalState.new

      stub_direct_dependencies("syntax_tree" => "1.2.3")
      stub_all_dependencies("syntax_tree", "rubocop")
      state.stubs(:dot_rubocop_yml_present).returns(true)

      state.apply_options({ initializationOptions: { formatter: "auto" } })

      assert_equal("syntax_tree", state.formatter)
    end

    def test_watching_files_if_supported
      state = GlobalState.new
      state.apply_options({
        capabilities: {
          workspace: {
            didChangeWatchedFiles: {
              dynamicRegistration: true,
              relativePatternSupport: true,
            },
          },
        },
      })
      assert(state.supports_watching_files)
    end

    def test_watching_files_if_not_supported
      state = GlobalState.new
      state.apply_options({
        capabilities: {
          workspace: {
            didChangeWatchedFiles: {
              dynamicRegistration: true,
              relativePatternSupport: false,
            },
          },
        },
      })
      refute(state.supports_watching_files)
    end

    def test_watching_files_if_not_reported
      state = GlobalState.new
      state.apply_options({
        capabilities: {
          workspace: {},
        },
      })
      refute(state.supports_watching_files)
    end

    def test_linter_specification
      state = GlobalState.new
      state.apply_options({
        initializationOptions: { linters: ["rubocop", "brakeman"] },
      })

      assert_equal(["rubocop", "brakeman"], state.instance_variable_get(:@linters))
    end

    def test_linter_auto_detection
      stub_direct_dependencies("rubocop" => "1.2.3")
      state = GlobalState.new
      state.apply_options({})

      assert_equal(["rubocop"], state.instance_variable_get(:@linters))
    end

    def test_specifying_empty_linters
      stub_direct_dependencies("rubocop" => "1.2.3")
      state = GlobalState.new
      state.apply_options({
        initializationOptions: { linters: [] },
      })

      assert_empty(state.instance_variable_get(:@linters))
    end

    private

    def stub_direct_dependencies(dependencies)
      Bundler.locked_gems.stubs(dependencies: dependencies)
    end

    BundlerSpec = Struct.new(:name)
    def stub_all_dependencies(*dependencies)
      Bundler.locked_gems.stubs(specs: dependencies.map { BundlerSpec.new(_1) })
    end

    def stub_workspace_file_exists(path)
      File.expects(:exist?).with("#{Dir.pwd}/#{path}").returns(true)
    end
  end
end
