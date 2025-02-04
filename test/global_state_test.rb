# typed: true
# frozen_string_literal: true

require "test_helper"

module RubyLsp
  class GlobalStateTest < Minitest::Test
    def test_apply_option_selects_formatter
      state = GlobalState.new
      state.apply_options({ initializationOptions: { formatter: "syntax_tree" } })
      assert_equal("syntax_tree", state.formatter)
    end

    def test_applying_auto_formatter_invokes_detection
      state = GlobalState.new
      state.apply_options({ initializationOptions: { formatter: "auto" } })
      assert_equal("rubocop_internal", state.formatter)
    end

    def test_applying_auto_formatter_with_rubocop_extension
      state = GlobalState.new
      stub_direct_dependencies("rubocop-rails" => "1.2.3")
      state.apply_options({ initializationOptions: { formatter: "auto" } })
      assert_equal("rubocop_internal", state.formatter)
    end

    def test_applying_auto_formatter_with_rubocop_as_transitive_dependency
      state = GlobalState.new

      stub_direct_dependencies("gem_with_config" => "1.2.3")
      stub_all_dependencies("gem_with_config", "rubocop")
      state.stubs(:dot_rubocop_yml_present).returns(true)

      state.apply_options({ initializationOptions: { formatter: "auto" } })

      assert_equal("rubocop_internal", state.formatter)
    end

    def test_applying_auto_formatter_with_rubocop_as_transitive_dependency_without_config
      state = GlobalState.new

      stub_direct_dependencies("gem_with_config" => "1.2.3")
      stub_all_dependencies("gem_with_config", "rubocop")
      state.stubs(:dot_rubocop_yml_present).returns(false)

      state.apply_options({ initializationOptions: { formatter: "auto" } })

      assert_equal("none", state.formatter)
    end

    def test_applying_auto_formatter_with_rubocop_as_transitive_dependency_and_syntax_tree
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
      assert(state.client_capabilities.supports_watching_files)
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
      refute(state.client_capabilities.supports_watching_files)
    end

    def test_watching_files_if_not_reported
      state = GlobalState.new
      state.apply_options({
        capabilities: {
          workspace: {},
        },
      })
      refute(state.client_capabilities.supports_watching_files)
    end

    def test_linter_specification
      ::RuboCop::Version.const_set(:STRING, "1.68.0")
      state = GlobalState.new
      state.apply_options({
        initializationOptions: { linters: ["rubocop", "brakeman"] },
      })

      assert_equal(["brakeman", "rubocop_internal"], state.instance_variable_get(:@linters))
    end

    def test_linter_auto_detection
      stub_direct_dependencies("rubocop" => "1.2.3")
      state = GlobalState.new
      state.apply_options({})

      assert_equal(["rubocop_internal"], state.instance_variable_get(:@linters))
    end

    def test_specifying_empty_linters
      stub_direct_dependencies("rubocop" => "1.2.3")
      state = GlobalState.new
      state.apply_options({
        initializationOptions: { linters: [] },
      })

      assert_empty(state.instance_variable_get(:@linters))
    end

    def test_linter_auto_detection_with_rubocop_as_transitive_dependency
      state = GlobalState.new

      stub_direct_dependencies("gem_with_config" => "1.2.3")
      stub_all_dependencies("gem_with_config", "rubocop")
      state.stubs(:dot_rubocop_yml_present).returns(true)

      state.apply_options({})

      assert_includes(state.instance_variable_get(:@linters), "rubocop_internal")
    end

    def test_type_checker_is_detected_based_on_transitive_sorbet_static
      state = GlobalState.new

      Bundler.locked_gems.stubs(dependencies: {})
      stub_all_dependencies("sorbet-static")
      state.apply_options({ initializationOptions: {} })

      assert_predicate(state, :has_type_checker)
    end

    def test_addon_settings_are_stored
      global_state = GlobalState.new

      global_state.apply_options({
        initializationOptions: {
          addonSettings: {
            "Ruby LSP Rails" => { runtimeServerEnabled: false },
          },
        },
      })

      assert_equal({ runtimeServerEnabled: false }, global_state.settings_for_addon("Ruby LSP Rails"))
    end

    def test_delegates_supports_watching_files_to_client_capabilities
      global_state = GlobalState.new
      global_state.client_capabilities.expects(:supports_watching_files).returns(true)
      global_state.supports_watching_files
    end

    def test_feature_flags_are_processed_by_apply_options
      state = GlobalState.new

      state.apply_options({
        initializationOptions: {
          enabledFeatureFlags: {
            semantic_highlighting: true,
            code_lens: false,
          },
        },
      })

      assert(state.enabled_feature?(:semantic_highlighting))
      refute(state.enabled_feature?(:code_lens))
      assert_nil(state.enabled_feature?(:unknown_flag))
    end

    def test_enabled_feature_always_returns_true_if_all_are_enabled
      state = GlobalState.new

      state.apply_options({
        initializationOptions: {
          enabledFeatureFlags: {
            all: true,
          },
        },
      })

      assert(state.enabled_feature?(:whatever))
    end

    # TODO: index tests only when open, and remove when closed

    def test_test_library_for_group_for_minitest_test
      # TODO: consider nesting
      code = <<~RUBY
        module MyTests
          class TestFoo < Minitest::Test
          end
        end
        class Minitest::Test
        end
      RUBY
      first_class = Prism.parse(code).value.statements.body.first

      state = GlobalState.new
      uri = URI::Generic.from_path(path: "/test.rb")
      state.index.index_single(uri, code)

      assert_equal("minitest", state.test_library_for_group(first_class))
    end

    def test_notifies_the_user_when_using_rubocop_addon_through_linters
      ::RuboCop::Version.const_set(:STRING, "1.70.0")

      state = GlobalState.new
      notifications = state.apply_options({ initializationOptions: { linters: ["rubocop"] } })

      log = notifications.find do |n|
        n.method == "window/logMessage" && T.unsafe(n.params).message.include?("RuboCop v1.70.0")
      end
      refute_nil(log)
      assert_equal(["rubocop"], state.instance_variable_get(:@linters))
    end

    def test_notifies_the_user_when_using_rubocop_addon_through_formatter
      ::RuboCop::Version.const_set(:STRING, "1.70.0")

      state = GlobalState.new
      notifications = state.apply_options({ initializationOptions: { formatter: "rubocop" } })

      log = notifications.find do |n|
        n.method == "window/logMessage" && T.unsafe(n.params).message.include?("RuboCop v1.70.0")
      end
      refute_nil(log)
      assert_equal("rubocop", state.formatter)
    end

    def test_falls_back_to_internal_integration_for_linters_if_rubocop_has_no_addon
      ::RuboCop::Version.const_set(:STRING, "1.68.0")

      state = GlobalState.new
      notifications = state.apply_options({ initializationOptions: { linters: ["rubocop"] } })

      log = notifications.find do |n|
        n.method == "window/logMessage" && T.unsafe(n.params).message.include?("RuboCop v1.70.0")
      end
      refute_nil(log)
      assert_equal(["rubocop_internal"], state.instance_variable_get(:@linters))
    end

    def test_falls_back_to_internal_integration_for_formatters_if_rubocop_has_no_addon
      ::RuboCop::Version.const_set(:STRING, "1.68.0")

      state = GlobalState.new
      notifications = state.apply_options({ initializationOptions: { formatter: "rubocop" } })

      log = notifications.find do |n|
        n.method == "window/logMessage" && T.unsafe(n.params).message.include?("RuboCop v1.70.0")
      end
      refute_nil(log)
      assert_equal("rubocop_internal", state.formatter)
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
