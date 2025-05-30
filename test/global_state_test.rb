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

    def test_notifies_the_user_when_using_rubocop_addon_through_linters
      ::RuboCop::Version.const_set(:STRING, "1.70.0")

      state = GlobalState.new
      notifications = state.apply_options({ initializationOptions: { linters: ["rubocop"] } })

      log = notifications.find do |n|
        params = n.params #: as untyped
        n.method == "window/logMessage" && params.message.include?("RuboCop v1.70.0")
      end
      refute_nil(log)
      assert_equal(["rubocop"], state.instance_variable_get(:@linters))
    end

    def test_notifies_the_user_when_using_rubocop_addon_through_formatter
      ::RuboCop::Version.const_set(:STRING, "1.70.0")

      state = GlobalState.new
      notifications = state.apply_options({ initializationOptions: { formatter: "rubocop" } })

      log = notifications.find do |n|
        params = n.params #: as untyped
        n.method == "window/logMessage" && params.message.include?("RuboCop v1.70.0")
      end
      refute_nil(log)
      assert_equal("rubocop", state.formatter)
    end

    def test_falls_back_to_internal_integration_for_linters_if_rubocop_has_no_addon
      ::RuboCop::Version.const_set(:STRING, "1.68.0")

      state = GlobalState.new
      notifications = state.apply_options({ initializationOptions: { linters: ["rubocop"] } })

      log = notifications.find do |n|
        params = n.params #: as untyped
        n.method == "window/logMessage" && params.message.include?("RuboCop v1.70.0")
      end
      refute_nil(log)
      assert_equal(["rubocop_internal"], state.instance_variable_get(:@linters))
    end

    def test_falls_back_to_internal_integration_for_formatters_if_rubocop_has_no_addon
      ::RuboCop::Version.const_set(:STRING, "1.68.0")

      state = GlobalState.new
      notifications = state.apply_options({ initializationOptions: { formatter: "rubocop" } })

      log = notifications.find do |n|
        params = n.params #: as untyped
        n.method == "window/logMessage" && params.message.include?("RuboCop v1.70.0")
      end
      refute_nil(log)
      assert_equal("rubocop_internal", state.formatter)
    end

    def test_saves_telemetry_machine_id
      state = GlobalState.new
      assert_nil(state.telemetry_machine_id)

      state.apply_options({ initializationOptions: { telemetryMachineId: "test_machine_id" } })
      assert_equal("test_machine_id", state.telemetry_machine_id)
    end

    def test_detects_vscode_ruby_mcp
      state = GlobalState.new

      # Stub the bin_rails_present method
      state.stubs(:bin_rails_present).returns(false)

      stub_workspace_file_does_not_exist(".cursor/mcp.json")
      stub_workspace_file_exists(".vscode/mcp.json")
      File.stubs(:read).with("#{Dir.pwd}/.vscode/mcp.json").returns('{"servers":{"rubyMcp":{"command":"path"}}}')

      state.apply_options({})
      assert(state.uses_ruby_mcp)
    end

    def test_detects_cursor_ruby_mcp
      state = GlobalState.new

      # Stub the bin_rails_present method
      state.stubs(:bin_rails_present).returns(false)

      stub_workspace_file_does_not_exist(".vscode/mcp.json")
      stub_workspace_file_exists(".cursor/mcp.json")
      File.stubs(:read).with("#{Dir.pwd}/.cursor/mcp.json").returns('{"mcpServers":{"rubyMcp":{"command":"path"}}}')

      state.apply_options({})
      assert(state.uses_ruby_mcp)
    end

    def test_does_not_detect_ruby_mcp_when_no_files_exist
      state = GlobalState.new

      # Stub the bin_rails_present method
      state.stubs(:bin_rails_present).returns(false)

      stub_workspace_file_does_not_exist(".vscode/mcp.json")
      stub_workspace_file_does_not_exist(".cursor/mcp.json")

      state.apply_options({})
      refute(state.uses_ruby_mcp)
    end

    def test_does_not_detect_ruby_mcp_when_vscode_has_no_config
      state = GlobalState.new

      # Stub the bin_rails_present method
      state.stubs(:bin_rails_present).returns(false)

      stub_workspace_file_exists(".vscode/mcp.json")
      stub_workspace_file_does_not_exist(".cursor/mcp.json")
      File.stubs(:read).with("#{Dir.pwd}/.vscode/mcp.json").returns('{"servers":{"otherServer":{"command":"path"}}}')

      state.apply_options({})
      refute(state.uses_ruby_mcp)
    end

    def test_does_not_detect_ruby_mcp_when_cursor_has_no_config
      state = GlobalState.new

      # Stub the bin_rails_present method
      state.stubs(:bin_rails_present).returns(false)

      stub_workspace_file_does_not_exist(".vscode/mcp.json")
      stub_workspace_file_exists(".cursor/mcp.json")
      File.stubs(:read).with("#{Dir.pwd}/.cursor/mcp.json").returns('{"mcpServers":{"otherServer":{"command":"path"}}}')

      state.apply_options({})
      refute(state.uses_ruby_mcp)
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
      File.stubs(:exist?).with("#{Dir.pwd}/#{path}").returns(true)
    end

    def stub_workspace_file_does_not_exist(path)
      File.stubs(:exist?).with("#{Dir.pwd}/#{path}").returns(false)
    end
  end
end
