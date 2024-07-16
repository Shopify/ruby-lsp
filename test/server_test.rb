# typed: true
# frozen_string_literal: true

require "test_helper"

class ServerTest < Minitest::Test
  def setup
    @server = RubyLsp::Server.new(test_mode: true)
  end

  def teardown
    @server.run_shutdown
  end

  def test_initialize_enabled_features_with_array
    capture_subprocess_io do
      @server.process_message({
        id: 1,
        method: "initialize",
        params: {
          initializationOptions: { enabledFeatures: ["semanticHighlighting"] },
          capabilities: { general: { positionEncodings: ["utf-8"] } },
        },
      })
    end

    hash = JSON.parse(@server.pop_response.response.to_json)
    capabilities = hash["capabilities"]

    # TextSynchronization + encodings + semanticHighlighting + experimental
    assert_equal(4, capabilities.length)
    assert_includes(capabilities, "semanticTokensProvider")
  end

  def test_initialize_enabled_features_with_hash
    capture_subprocess_io do
      @server.process_message({
        id: 1,
        method: "initialize",
        params: {
          initializationOptions: { enabledFeatures: { "semanticHighlighting" => false } },
          capabilities: { general: { positionEncodings: ["utf-8"] } },
        },
      })
    end

    hash = JSON.parse(@server.pop_response.response.to_json)
    capabilities = hash["capabilities"]

    # Only semantic highlighting is turned off because all others default to true when configuring with a hash
    refute_includes(capabilities, "semanticTokensProvider")
  end

  def test_initialize_enabled_features_with_no_configuration
    capture_subprocess_io do
      @server.process_message({
        id: 1,
        method: "initialize",
        params: {
          initializationOptions: {},
          capabilities: { general: { positionEncodings: ["utf-8"] } },
        },
      })
    end

    hash = JSON.parse(@server.pop_response.response.to_json)
    capabilities = hash["capabilities"]

    # All features are enabled by default
    assert_includes(capabilities, "semanticTokensProvider")
  end

  def test_initialize_defaults_to_utf_8_if_present
    capture_subprocess_io do
      @server.process_message({
        id: 1,
        method: "initialize",
        params: {
          initializationOptions: {},
          capabilities: { general: { positionEncodings: ["utf-8", "utf-16"] } },
        },
      })
    end

    hash = JSON.parse(@server.pop_response.response.to_json)

    # All features are enabled by default
    assert_includes("utf-8", hash.dig("capabilities", "positionEncoding"))
  end

  def test_initialize_uses_utf_16_if_utf_8_is_not_present
    capture_subprocess_io do
      @server.process_message({
        id: 1,
        method: "initialize",
        params: {
          initializationOptions: {},
          capabilities: { general: { positionEncodings: ["utf-16"] } },
        },
      })
    end

    hash = JSON.parse(@server.pop_response.response.to_json)

    # All features are enabled by default
    assert_includes("utf-16", hash.dig("capabilities", "positionEncoding"))
  end

  def test_initialize_uses_utf_16_if_no_encodings_are_specified
    capture_subprocess_io do
      @server.process_message({
        id: 1,
        method: "initialize",
        params: {
          initializationOptions: {},
          capabilities: { general: { positionEncodings: [] } },
        },
      })
    end

    hash = JSON.parse(@server.pop_response.response.to_json)

    # All features are enabled by default
    assert_includes("utf-16", hash.dig("capabilities", "positionEncoding"))
  end

  def test_server_info_includes_version
    capture_subprocess_io do
      @server.process_message({
        id: 1,
        method: "initialize",
        params: {
          initializationOptions: {},
          capabilities: {},
        },
      })
    end

    hash = JSON.parse(@server.pop_response.response.to_json)
    assert_equal(RubyLsp::VERSION, hash.dig("serverInfo", "version"))
  end

  def test_server_info_includes_formatter
    @server.global_state.expects(:formatter).twice.returns("rubocop")
    capture_subprocess_io do
      @server.process_message({
        id: 1,
        method: "initialize",
        params: {
          initializationOptions: {},
          capabilities: {},
        },
      })
    end

    hash = JSON.parse(@server.pop_response.response.to_json)
    assert_equal("rubocop", hash.dig("formatter"))
  end

  def test_initialized_populates_index
    capture_subprocess_io do
      @server.process_message({ method: "initialized" })

      assert_equal("$/progress", @server.pop_response.method)
      assert_equal("$/progress", @server.pop_response.method)
      assert_equal("$/progress", @server.pop_response.method)
      assert_equal("$/progress", @server.pop_response.method)

      refute_empty(@server.global_state.index)
    end
  end

  def test_initialized_recovers_from_indexing_failures
    @server.global_state.index.expects(:index_all).once.raises(StandardError, "boom!")
    capture_subprocess_io do
      @server.process_message({ method: "initialized" })
    end

    notification = @server.pop_response
    assert_equal("window/showMessage", notification.method)
    assert_equal(
      "Error while indexing: boom!",
      T.cast(notification.params, RubyLsp::Interface::ShowMessageParams).message,
    )
  end

  def test_formatting_errors_push_window_notification
    @server.global_state.expects(:formatter).raises(StandardError, "boom").once

    @server.process_message({
      id: 1,
      method: "textDocument/formatting",
      params: {
        textDocument: { uri: URI("file://#{__FILE__}") },
      },
    })

    notification = @server.pop_response

    assert_instance_of(RubyLsp::Notification, notification)
    assert_equal("window/showMessage", notification.method)
    assert_equal(
      "Formatting error: boom",
      T.cast(notification.params, RubyLsp::Interface::ShowMessageParams).message,
    )
  end

  def test_returns_nil_diagnostics_and_formatting_for_files_outside_workspace
    capture_subprocess_io do
      @server.process_message({
        id: 1,
        method: "initialize",
        params: {
          initializationOptions: { enabledFeatures: ["formatting", "diagnostics"] },
          capabilities: { general: { positionEncodings: ["utf-8"] } },
          workspaceFolders: [{ uri: URI::Generic.from_path(path: Dir.pwd).to_standardized_path }],
        },
      })
    end

    # File watching, progress notifications and initialize response
    @server.pop_response
    @server.pop_response
    @server.pop_response

    @server.process_message({
      id: 2,
      method: "textDocument/formatting",
      params: {
        textDocument: { uri: URI::Generic.from_path(path: "/foo.rb") },
      },
    })

    assert_nil(@server.pop_response.response)

    @server.process_message({
      id: 3,
      method: "textDocument/diagnostic",
      params: {
        textDocument: { uri: URI::Generic.from_path(path: "/foo.rb") },
      },
    })

    assert_nil(@server.pop_response.response)
  end

  def test_did_close_clears_diagnostics
    @server.process_message({
      method: "textDocument/didClose",
      params: {
        textDocument: { uri: URI::Generic.from_path(path: "/fake.rb") },
      },
    })

    notification = T.must(@server.pop_response)
    assert_equal("textDocument/publishDiagnostics", notification.method)
    assert_empty(T.cast(notification.params, RubyLsp::Interface::PublishDiagnosticsParams).diagnostics)
  end

  def test_initialize_features_with_default_configuration
    capture_subprocess_io do
      @server.process_message({ method: "initialized" })
    end
    store = @server.instance_variable_get(:@store)

    refute(store.features_configuration.dig(:inlayHint).enabled?(:implicitRescue))
    refute(store.features_configuration.dig(:inlayHint).enabled?(:implicitHashValue))
  end

  def test_initialize_features_with_provided_configuration
    capture_subprocess_io do
      @server.process_message(id: 1, method: "initialize", params: {
        initializationOptions: {
          featuresConfiguration: {
            inlayHint: {
              implicitRescue: true,
              implicitHashValue: true,
            },
          },
        },
      })
    end

    store = @server.instance_variable_get(:@store)
    assert(store.features_configuration.dig(:inlayHint).enabled?(:implicitRescue))
    assert(store.features_configuration.dig(:inlayHint).enabled?(:implicitHashValue))
  end

  def test_initialize_features_with_partially_provided_configuration
    capture_subprocess_io do
      @server.process_message(id: 1, method: "initialize", params: {
        initializationOptions: {
          featuresConfiguration: {
            inlayHint: {
              implicitHashValue: true,
            },
          },
        },
      })
    end

    store = @server.instance_variable_get(:@store)

    refute(store.features_configuration.dig(:inlayHint).enabled?(:implicitRescue))
    assert(store.features_configuration.dig(:inlayHint).enabled?(:implicitHashValue))
  end

  def test_initialize_features_with_enable_all_configuration
    capture_subprocess_io do
      @server.process_message(id: 1, method: "initialize", params: {
        initializationOptions: {
          featuresConfiguration: {
            inlayHint: {
              enableAll: true,
            },
          },
        },
      })
    end

    store = @server.instance_variable_get(:@store)

    assert(store.features_configuration.dig(:inlayHint).enabled?(:implicitRescue))
    assert(store.features_configuration.dig(:inlayHint).enabled?(:implicitHashValue))
  end

  def test_handles_invalid_configuration
    File.write(".index.yml", "} invalid yaml")

    capture_subprocess_io do
      @server.process_message(id: 1, method: "initialize", params: {})
    end

    @server.pop_response
    notification = @server.pop_response
    assert_equal("window/showMessage", notification.method)
    assert_match(
      /Syntax error while loading configuration/,
      T.cast(notification.params, RubyLsp::Interface::ShowMessageParams).message,
    )
  ensure
    FileUtils.rm(".index.yml")
  end

  def test_shows_error_if_formatter_set_to_rubocop_but_rubocop_not_available
    capture_subprocess_io do
      @server.process_message(id: 1, method: "initialize", params: {
        initializationOptions: { formatter: "rubocop" },
      })

      @server.global_state.register_formatter("rubocop", RubyLsp::Requests::Support::RuboCopFormatter.new)
      with_uninstalled_rubocop do
        @server.process_message({ method: "initialized" })
      end

      assert_equal("none", @server.global_state.formatter)

      # Remove the initialization notifications
      @server.pop_response
      @server.pop_response
      @server.pop_response

      notification = @server.pop_response

      assert_equal("window/showMessage", notification.method)
      assert_equal(
        "Ruby LSP formatter is set to `rubocop` but RuboCop was not found in the Gemfile or gemspec.",
        T.cast(notification.params, RubyLsp::Interface::ShowMessageParams).message,
      )
    end
  end

  def test_initialize_sets_client_name
    capture_subprocess_io do
      @server.process_message(id: 1, method: "initialize", params: {
        clientInfo: { name: "Foo" },
      })
    end

    store = @server.instance_variable_get(:@store)
    assert_equal("Foo", store.client_name)
  end

  def test_workspace_dependencies
    @server.process_message({ id: 1, method: "rubyLsp/workspace/dependencies" })

    @server.pop_response.response.each do |gem_info|
      assert_instance_of(String, gem_info[:name])
      assert_instance_of(Gem::Version, gem_info[:version])
      assert_instance_of(String, gem_info[:path])
      assert(gem_info[:dependency].is_a?(TrueClass) || gem_info[:dependency].is_a?(FalseClass))
    end
  end

  def test_backtrace_is_printed_to_stderr_on_exceptions
    @server.expects(:workspace_dependencies).raises(StandardError, "boom")

    _stdout, stderr = capture_io do
      @server.process_message({
        id: 1,
        method: "rubyLsp/workspace/dependencies",
        params: {},
      })
    end

    assert_match(/boom/, stderr)
    assert_match(%r{ruby-lsp/lib/ruby_lsp/server\.rb:\d+:in `process_message'}, stderr)
  end

  def test_changed_file_only_indexes_ruby
    @server.global_state.index.expects(:index_single).once.with do |indexable|
      indexable.full_path == "/foo.rb"
    end
    @server.process_message({
      method: "workspace/didChangeWatchedFiles",
      params: {
        changes: [
          {
            uri: URI("file:///foo.rb"),
            type: RubyLsp::Constant::FileChangeType::CREATED,
          },
          {
            uri: URI("file:///.rubocop.yml"),
            type: RubyLsp::Constant::FileChangeType::CREATED,
          },
        ],
      },
    })
  end

  def test_workspace_addons
    create_test_addons
    @server.load_addons

    @server.process_message({ id: 1, method: "rubyLsp/workspace/addons" })

    addon_error_notification = @server.pop_response
    assert_equal("window/showMessage", addon_error_notification.method)
    assert_equal("Error loading addons:\n\nBar:\n  boom\n", addon_error_notification.params.message)
    addons_info = @server.pop_response.response

    assert_equal("Foo", addons_info[0][:name])
    refute(addons_info[0][:errored])

    assert_equal("Bar", addons_info[1][:name])
    assert(addons_info[1][:errored])
  ensure
    RubyLsp::Addon.addons.clear
    RubyLsp::Addon.addon_classes.clear
  end

  def test_errors_include_telemetry_data
    @server.expects(:workspace_symbol).raises(StandardError, "boom")

    capture_io do
      @server.process_message(id: 1, method: "workspace/symbol", params: { query: "" })
    end

    error = @server.pop_response
    assert_instance_of(RubyLsp::Error, error)

    data = error.to_hash.dig(:error, :data)
    assert_equal("boom", data[:errorMessage])
    assert_equal("StandardError", data[:errorClass])
    assert_match("mocha/exception_raiser.rb", data[:backtrace])
  end

  def test_handles_editor_indexing_settings
    capture_io do
      @server.process_message({
        id: 1,
        method: "initialize",
        params: {
          initializationOptions: {
            indexing: {
              excludedGems: ["foo_gem"],
              includedGems: ["bar_gem"],
            },
          },
        },
      })
    end

    assert_includes(RubyIndexer.configuration.instance_variable_get(:@excluded_gems), "foo_gem")
    assert_includes(RubyIndexer.configuration.instance_variable_get(:@included_gems), "bar_gem")
  end

  private

  def with_uninstalled_rubocop(&block)
    rubocop_paths = $LOAD_PATH.select { |path| path.include?("gems/rubocop") }
    rubocop_paths.each { |path| $LOAD_PATH.delete(path) }

    $LOADED_FEATURES.delete_if do |path|
      path.include?("ruby_lsp/requests/support/rubocop_runner") ||
        path.include?("ruby_lsp/requests/support/rubocop_formatter")
    end

    unload_rubocop_runner
    block.call
  ensure
    $LOAD_PATH.unshift(*rubocop_paths)
    unload_rubocop_runner
    require "ruby_lsp/requests/support/rubocop_runner"
    require "ruby_lsp/requests/support/rubocop_formatter"
  end

  def unload_rubocop_runner
    RubyLsp::Requests::Support.send(:remove_const, :RuboCopRunner)
    RubyLsp::Requests::Support.send(:remove_const, :RuboCopFormatter)
  rescue NameError
    # Depending on which tests have run prior to this one, the classes may or may not be defined
  end

  def create_test_addons
    Class.new(RubyLsp::Addon) do
      def activate(global_state, outgoing_queue); end

      def name
        "Foo"
      end

      def deactivate; end
    end

    Class.new(RubyLsp::Addon) do
      def activate(global_state, outgoing_queue)
        # simulates failed addon activation
        raise "boom"
      end

      def name
        "Bar"
      end

      def deactivate; end
    end
  end
end
