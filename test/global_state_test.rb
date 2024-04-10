# typed: true
# frozen_string_literal: true

require "test_helper"

module RubyLsp
  class GlobalStateTest < Minitest::Test
    def test_detects_no_test_library_when_there_are_no_dependencies
      stub_dependencies({})

      assert_equal("unknown", GlobalState.new.test_library)
    end

    def test_detects_minitest
      stub_dependencies("minitest" => "1.2.3")

      assert_equal("minitest", GlobalState.new.test_library)
    end

    def test_does_not_detect_minitest_related_gems_as_minitest
      stub_dependencies("minitest-reporters" => "1.2.3")

      assert_equal("unknown", GlobalState.new.test_library)
    end

    def test_detects_test_unit
      stub_dependencies("test-unit" => "1.2.3")

      assert_equal("test-unit", GlobalState.new.test_library)
    end

    def test_detects_dependencies_in_gemspecs
      assert(GlobalState.new.direct_dependency?(/^prism$/))
    end

    def test_detects_rails_if_minitest_is_present_and_bin_rails_exists
      stub_dependencies("minitest" => "1.2.3")
      File.expects(:exist?).with("#{Dir.pwd}/bin/rails").once.returns(true)

      assert_equal("rails", GlobalState.new.test_library)
    end

    def test_detects_rspec_if_both_rails_and_rspec_are_present
      stub_dependencies("rspec" => "1.2.3")
      File.expects(:exist?).never

      assert_equal("rspec", GlobalState.new.test_library)
    end

    def test_direct_dependency_returns_false_outside_of_bundle
      File.expects(:file?).at_least_once.returns(false)
      stub_dependencies({})
      refute(GlobalState.new.direct_dependency?(/^ruby-lsp/))
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

    private

    def stub_dependencies(dependencies)
      Bundler.locked_gems.stubs(dependencies: dependencies)
    end
  end
end
