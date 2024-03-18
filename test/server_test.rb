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

    # TextSynchronization + encodings + semanticHighlighting
    assert_equal(3, capabilities.length)
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
    RubyLsp::DependencyDetector.instance.expects(:detected_formatter).returns("rubocop")
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

      assert_equal("$/progress", @server.pop_response.message)
      assert_equal("$/progress", @server.pop_response.message)
      assert_equal("$/progress", @server.pop_response.message)
      assert_equal("$/progress", @server.pop_response.message)

      index = @server.index
      refute_empty(index.instance_variable_get(:@entries))
    end
  end

  def test_initialized_recovers_from_indexing_failures
    @server.index.expects(:index_all).once.raises(StandardError, "boom!")
    capture_subprocess_io do
      @server.process_message({ method: "initialized" })
    end

    notification = @server.pop_response
    assert_equal("window/showMessage", notification.message)
    assert_equal(
      "Error while indexing: boom!",
      T.cast(notification.params, RubyLsp::Interface::ShowMessageParams).message,
    )
  end

  def test_formatting_errors_push_window_notification
    @server.instance_variable_get(:@store).expects(:formatter).raises(StandardError, "boom").once

    @server.process_message({
      id: 1,
      method: "textDocument/formatting",
      params: {
        textDocument: { uri: URI("file://#{__FILE__}") },
      },
    })

    notification = @server.pop_response

    assert_instance_of(RubyLsp::Notification, notification)
    assert_equal("window/showMessage", notification.message)
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
    assert_equal("textDocument/publishDiagnostics", notification.message)
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

  def test_detects_rubocop_if_direct_dependency
    stub_dependencies(rubocop: true, syntax_tree: false)

    capture_subprocess_io do
      @server.process_message(id: 1, method: "initialize", params: {
        initializationOptions: { formatter: "auto" },
      })
    end

    store = @server.instance_variable_get(:@store)
    assert_equal("rubocop", store.formatter)
  end

  def test_detects_syntax_tree_if_direct_dependency
    stub_dependencies(rubocop: false, syntax_tree: true)
    capture_subprocess_io do
      @server.process_message(id: 1, method: "initialize", params: {
        initializationOptions: { formatter: "auto" },
      })
    end

    store = @server.instance_variable_get(:@store)
    assert_equal("syntax_tree", store.formatter)
  end

  def test_gives_rubocop_precedence_if_syntax_tree_also_present
    stub_dependencies(rubocop: true, syntax_tree: true)
    capture_subprocess_io do
      @server.process_message(id: 1, method: "initialize", params: {
        initializationOptions: { formatter: "auto" },
      })
    end

    store = @server.instance_variable_get(:@store)
    assert_equal("rubocop", store.formatter)
  end

  def test_sets_formatter_to_none_if_neither_rubocop_or_syntax_tree_are_present
    stub_dependencies(rubocop: false, syntax_tree: false)
    capture_subprocess_io do
      @server.process_message(id: 1, method: "initialize", params: {
        initializationOptions: { formatter: "auto" },
      })
    end

    store = @server.instance_variable_get(:@store)
    assert_equal("none", store.formatter)
  end

  def test_shows_error_if_formatter_set_to_rubocop_but_rubocop_not_available
    with_uninstalled_rubocop do
      capture_subprocess_io do
        @server.process_message(id: 1, method: "initialize", params: {
          initializationOptions: { formatter: "rubocop" },
        })
        @server.process_message({ method: "initialized" })

        store = @server.instance_variable_get(:@store)
        assert_equal("none", store.formatter)

        # Remove the initialization notifications
        @server.pop_response
        @server.pop_response
        @server.pop_response

        notification = @server.pop_response

        assert_equal("window/showMessage", notification.message)
        assert_equal(
          "Ruby LSP formatter is set to `rubocop` but RuboCop was not found in the Gemfile or gemspec.",
          T.cast(notification.params, RubyLsp::Interface::ShowMessageParams).message,
        )
      end
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

  private

  def with_uninstalled_rubocop(&block)
    rubocop_paths = $LOAD_PATH.select { |path| path.include?("gems/rubocop") }
    rubocop_paths.each { |path| $LOAD_PATH.delete(path) }

    $LOADED_FEATURES.delete_if { |path| path.include?("ruby_lsp/requests/support/rubocop_runner") }

    unload_rubocop_runner
    block.call
  ensure
    $LOAD_PATH.unshift(*rubocop_paths)
    unload_rubocop_runner
    require "ruby_lsp/requests/support/rubocop_runner"
  end

  def unload_rubocop_runner
    RubyLsp::Requests::Support.send(:remove_const, :RuboCopRunner)
  rescue NameError
    # Depending on which tests have run prior to this one, `RuboCopRunner` may or may not be defined
  end

  def stub_dependencies(rubocop:, syntax_tree:)
    Singleton.__init__(RubyLsp::DependencyDetector)
    dependencies = {}
    dependencies["syntax_tree"] = "..." if syntax_tree
    dependencies["rubocop"] = "..." if rubocop
    Bundler.locked_gems.stubs(:dependencies).returns(dependencies)
  end
end
