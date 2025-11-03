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

    result = find_message(RubyLsp::Result, id: 1)
    hash = JSON.parse(result.response.to_json)
    capabilities = hash["capabilities"]

    # TextSynchronization + encodings + semanticHighlighting + range formatting + experimental
    assert_equal(5, capabilities.length)
    assert_includes(capabilities, "semanticTokensProvider")
  end

  def test_initialize_returns_bundle_env
    bundle_env_path = File.join(".ruby-lsp", "bundle_env")
    FileUtils.mkdir(".ruby-lsp") unless File.exist?(".ruby-lsp")
    File.write(bundle_env_path, "BUNDLE_PATH=vendor/bundle")
    @server.process_message({
      id: 1,
      method: "initialize",
      params: {
        initializationOptions: { enabledFeatures: [] },
        capabilities: { general: { positionEncodings: ["utf-8"] } },
      },
    })

    result = find_message(RubyLsp::Result, id: 1)
    hash = JSON.parse(result.response.to_json)

    begin
      assert_equal({ "BUNDLE_PATH" => "vendor/bundle" }, hash["bundle_env"])
    ensure
      FileUtils.rm(bundle_env_path) if File.exist?(bundle_env_path)
    end
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

    result = find_message(RubyLsp::Result, id: 1)
    hash = JSON.parse(result.response.to_json)
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

    result = find_message(RubyLsp::Result, id: 1)
    hash = JSON.parse(result.response.to_json)
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

    result = find_message(RubyLsp::Result, id: 1)
    hash = JSON.parse(result.response.to_json)

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

    result = find_message(RubyLsp::Result, id: 1)
    hash = JSON.parse(result.response.to_json)

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

    result = find_message(RubyLsp::Result, id: 1)
    hash = JSON.parse(result.response.to_json)

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

    result = find_message(RubyLsp::Result, id: 1)
    hash = JSON.parse(result.response.to_json)
    assert_equal(RubyLsp::VERSION, hash.dig("serverInfo", "version"))
  end

  def test_server_info_includes_formatter
    @server.global_state.expects(:formatter).twice.returns("rubocop_internal")
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

    result = find_message(RubyLsp::Result, id: 1)
    hash = JSON.parse(result.response.to_json)
    assert_equal("rubocop_internal", hash.dig("formatter"))
  end

  def test_initialized_recovers_from_indexing_failures
    @server.global_state.index.expects(:index_all).once.raises(StandardError, "boom!")
    capture_subprocess_io do
      @server.process_message({ method: "initialized" })
    end

    notification = @server.pop_response
    assert_equal("window/showMessage", notification.method)
    expected_message = "Error while indexing (see [troubleshooting steps]" \
      "(https://shopify.github.io/ruby-lsp/troubleshooting#indexing)): boom!"
    assert_equal(
      expected_message,
      notification.params #: as RubyLsp::Interface::ShowMessageParams
        .message,
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
      notification.params #: as RubyLsp::Interface::ShowMessageParams
        .message,
    )
  end

  def test_applies_workspace_uri_to_indexing_configs_even_if_no_configs_are_specified
    @server.process_message({
      id: 1,
      method: "initialize",
      params: {
        initializationOptions: {},
        capabilities: { general: { positionEncodings: ["utf-8"] } },
        workspaceFolders: [{ uri: URI::Generic.from_path(path: "/fake").to_s }],
      },
    })

    index = @server.instance_variable_get(:@global_state).index
    assert_equal("/fake", index.configuration.instance_variable_get(:@workspace_path))
  end

  def test_returns_nil_diagnostics_and_formatting_for_files_outside_workspace
    capture_subprocess_io do
      @server.process_message({
        id: 1,
        method: "initialize",
        params: {
          initializationOptions: { enabledFeatures: ["formatting", "diagnostics"] },
          capabilities: { general: { positionEncodings: ["utf-8"] } },
          workspaceFolders: [{ uri: URI::Generic.from_path(path: Dir.pwd).to_s }],
        },
      })
    end

    @server.process_message({
      id: 2,
      method: "textDocument/formatting",
      params: {
        textDocument: { uri: URI::Generic.from_path(path: "/foo.rb") },
      },
    })

    result = find_message(RubyLsp::Result, id: 2)
    assert_nil(result.response)

    @server.process_message({
      id: 3,
      method: "textDocument/diagnostic",
      params: {
        textDocument: { uri: URI::Generic.from_path(path: "/foo.rb") },
      },
    })

    result = find_message(RubyLsp::Result, id: 3)
    assert_nil(result.response)
  end

  def test_did_close_clears_diagnostics
    @server.process_message({
      method: "textDocument/didClose",
      params: {
        textDocument: { uri: URI::Generic.from_path(path: "/fake.rb") },
      },
    })

    notification = @server.pop_response #: as !nil
    assert_equal("textDocument/publishDiagnostics", notification.method)
    assert_empty(
      notification.params #: as RubyLsp::Interface::PublishDiagnosticsParams
        .diagnostics,
    )
  end

  def test_handles_invalid_configuration
    File.write(".index.yml", "} invalid yaml")

    capture_subprocess_io do
      @server.process_message(id: 1, method: "initialize", params: {})
    end

    notification = find_message(RubyLsp::Notification, "window/showMessage")
    assert_match(
      /Syntax error while loading configuration/,
      notification.params #: as RubyLsp::Interface::ShowMessageParams
        .message,
    )
  ensure
    FileUtils.rm(".index.yml")
  end

  def test_shows_error_if_formatter_set_to_rubocop_but_rubocop_not_available
    capture_subprocess_io do
      @server.process_message(id: 1, method: "initialize", params: {
        initializationOptions: { formatter: "rubocop_internal" },
      })

      @server.global_state.register_formatter("rubocop_internal", RubyLsp::Requests::Support::RuboCopFormatter.new)

      # Avoid trying to load add-ons because the RuboCop add-on will crash when the gem is artificially unloaded
      @server.expects(:load_addons)

      with_uninstalled_rubocop do
        @server.process_message({ method: "initialized" })
      end

      assert_equal("none", @server.global_state.formatter)

      notification = find_message(RubyLsp::Notification, "window/showMessage")

      assert_equal(
        "Ruby LSP formatter is set to `rubocop_internal` but RuboCop was not found in the Gemfile or gemspec.",
        notification.params #: as RubyLsp::Interface::ShowMessageParams
          .message,
      )
    end
  end

  def test_shows_error_if_formatter_set_to_rubocop_with_unavailable_config
    File.write(".rubocop", "-c .i_dont_exist.yml")
    capture_subprocess_io do
      @server.process_message({ method: "initialized" })

      notification = find_message(RubyLsp::Notification, "window/showMessage")
      assert_match(
        "RuboCop configuration error: Configuration file not found: #{Dir.pwd}/.i_dont_exist.yml",
        notification.params #: as RubyLsp::Interface::ShowMessageParams
          .message,
      )
    end
  ensure
    FileUtils.rm(".rubocop")
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

  def test_workspace_dependencies_does_not_fail_if_gems_are_not_installed
    Bundler.expects(:definition).raises(Bundler::GemNotFound)
    @server.process_message({ id: 1, method: "rubyLsp/workspace/dependencies" })

    assert_empty(@server.pop_response.response)
  end

  def test_workspace_dependencies_returns_empty_list_when_there_is_no_bundle
    @server.global_state.expects(:top_level_bundle).returns(false)
    @server.process_message({ id: 1, method: "rubyLsp/workspace/dependencies" })

    assert_empty(@server.pop_response.response)
  end

  def test_backtrace_is_printed_to_stderr_on_exceptions
    @server.expects(:workspace_dependencies).raises(StandardError, "boom")

    capture_io do
      @server.process_message({
        id: 1,
        method: "rubyLsp/workspace/dependencies",
        params: {},
      })
    end

    log = find_message(RubyLsp::Notification, "window/logMessage")
    content = log.params.message

    assert_match(/boom/, content)
    if RUBY_VERSION >= "3.4"
      assert_match(%r{ruby-lsp/lib/ruby_lsp/server\.rb:\d+:in 'RubyLsp::Server#process_message'}, content)
    else
      assert_match(%r{ruby-lsp/lib/ruby_lsp/server\.rb:\d+:in `process_message'}, content)
    end
  end

  def test_reply_to_workspace_configuration_modifies_global_state
    @server.instance_variable_set(:@sent_requests, {
      1 => RubyLsp::Request.workspace_configuration(
        1, section: "rubyLsp"
      ),
    })

    @server.process_message({
      id: 1,
      result: [{ formatter: "standard" }],
    })

    assert_equal("standard", @server.global_state.formatter)
  end

  def test_did_change_configuration_sends_workspace_configuration_request
    @server.process_message({
      id: 1,
      method: "workspace/didChangeConfiguration",
      params: {},
    })

    find_message(RubyLsp::Request, "workspace/configuration")
  end

  def test_changed_file_only_indexes_ruby
    path = File.join(Dir.pwd, "lib", "foo.rb")
    File.write(path, "class Foo\nend")
    uri = URI::Generic.from_path(path: path)

    begin
      @server.global_state.index.index_all(uris: [])
      @server.global_state.index.expects(:index_single).once.with do |uri|
        uri.full_path == path
      end

      @server.process_message({
        method: "workspace/didChangeWatchedFiles",
        params: {
          changes: [
            {
              uri: uri,
              type: RubyLsp::Constant::FileChangeType::CREATED,
            },
            {
              uri: URI("file:///.rubocop.yml"),
              type: RubyLsp::Constant::FileChangeType::CREATED,
            },
          ],
        },
      })
    ensure
      FileUtils.rm(path)
    end
  end

  def test_did_change_watched_files_does_not_fail_for_non_existing_files
    @server.global_state.index.index_all(uris: [])
    @server.process_message({
      method: "workspace/didChangeWatchedFiles",
      params: {
        changes: [
          {
            uri: URI::Generic.from_path(path: File.join(Dir.pwd, "lib", "non_existing.rb")).to_s,
            type: RubyLsp::Constant::FileChangeType::CREATED,
          },
        ],
      },
    })

    assert_raises(Timeout::Error) do
      Timeout.timeout(0.5) do
        notification = find_message(RubyLsp::Notification, "window/logMessage")
        flunk(notification.params.message)
      end
    end
  end

  def test_did_change_watched_files_handles_deletions
    path = File.join(Dir.pwd, "lib", "foo.rb")

    @server.global_state.index.expects(:delete).once.with do |uri|
      uri.full_path == path
    end

    uri = URI::Generic.from_path(path: path)

    @server.global_state.index.index_all(uris: [])
    @server.process_message({
      method: "workspace/didChangeWatchedFiles",
      params: {
        changes: [
          {
            uri: uri,
            type: RubyLsp::Constant::FileChangeType::DELETED,
          },
        ],
      },
    })
  end

  def test_did_change_watched_files_reports_addon_errors
    Class.new(RubyLsp::Addon) do
      def activate(global_state, outgoing_queue); end

      def workspace_did_change_watched_files(changes)
        raise StandardError, "boom"
      end

      def name
        "Foo"
      end

      def deactivate; end

      def version
        "0.1.0"
      end
    end

    Class.new(RubyLsp::Addon) do
      def activate(global_state, outgoing_queue); end

      def workspace_did_change_watched_files(changes)
      end

      def name
        "Bar"
      end

      def deactivate; end

      def version
        "0.1.0"
      end
    end

    @server.load_addons

    bar = RubyLsp::Addon.get("Bar", "0.1.0")
    bar.expects(:workspace_did_change_watched_files).once

    begin
      @server.global_state.index.index_all(uris: [])
      @server.process_message({
        method: "workspace/didChangeWatchedFiles",
        params: {
          changes: [
            {
              uri: URI::Generic.from_path(path: File.join(Dir.pwd, ".rubocop.yml")).to_s,
              type: RubyLsp::Constant::FileChangeType::CREATED,
            },
          ],
        },
      })

      message = @server.pop_response.params.message
      assert_match("Error in Foo add-on while processing watched file notifications", message)
      assert_match("boom", message)
    ensure
      RubyLsp::Addon.unload_addons
    end
  end

  def test_did_change_watched_files_processes_unique_change_entries
    @server.global_state.index.index_all(uris: [])
    @server.expects(:handle_rubocop_config_change).once
    @server.process_message({
      method: "workspace/didChangeWatchedFiles",
      params: {
        changes: [
          {
            uri: URI::Generic.from_path(path: File.join(Dir.pwd, ".rubocop.yml")).to_s,
            type: RubyLsp::Constant::FileChangeType::CHANGED,
          },
          {
            uri: URI::Generic.from_path(path: File.join(Dir.pwd, ".rubocop.yml")).to_s,
            type: RubyLsp::Constant::FileChangeType::CHANGED,
          },
        ],
      },
    })
  end

  def test_workspace_addons
    create_test_addons

    @server.stubs(:test_mode?).returns(false)
    @server.load_addons

    @server.process_message({ id: 1, method: "rubyLsp/workspace/addons" })

    addon_error_notification = find_message(RubyLsp::Notification, "window/showMessage")
    assert_equal("window/showMessage", addon_error_notification.method)
    assert_equal("Error loading add-ons:\n\nBar:\n  boom\n", addon_error_notification.params.message)
    addons_info = find_message(RubyLsp::Result, id: 1).response
    addons_info.delete_if { |addon_info| addon_info[:name] == "RuboCop" }

    assert_equal("Foo", addons_info[0][:name])
    assert_equal("0.1.0", addons_info[0][:version])
    refute(addons_info[0][:errored])

    assert_equal("Bar", addons_info[1][:name])
    # It doesn't define a `version` method
    assert_nil(addons_info[1][:version])
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

    assert_includes(@server.global_state.index.configuration.instance_variable_get(:@excluded_gems), "foo_gem")
    assert_includes(@server.global_state.index.configuration.instance_variable_get(:@included_gems), "bar_gem")
  end

  def test_closing_document_before_computing_features_does_not_error
    uri = URI("file:///foo.rb")

    capture_subprocess_io do
      @server.process_message({
        method: "textDocument/didOpen",
        params: {
          textDocument: {
            uri: uri,
            text: "class Foo\nend",
            version: 1,
            languageId: "ruby",
          },
        },
      })

      # Close the file in a thread to increase the chance that it gets closed during the processing of the 10 document
      # symbol requests below
      thread = Thread.new do
        @server.process_message({
          method: "textDocument/didClose",
          params: {
            textDocument: {
              uri: uri,
            },
          },
        })
      end

      10.times do |i|
        @server.process_message({
          id: i,
          method: "textDocument/documentSymbol",
          params: {
            textDocument: {
              uri: uri,
            },
          },
        })
      end

      thread.join
    end

    # Even if the thread technique, this test is not 100% reliable since it's trying to emulate a concurrency issue. If
    # we tried to always expect an error back, we would likely get infinite loops
    error = nil #: (RubyLsp::Error | RubyLsp::Message)?

    10.times do
      error = @server.pop_response
      break if error.is_a?(RubyLsp::Error)
    end

    if error.is_a?(RubyLsp::Error)
      assert_instance_of(RubyLsp::Error, error)
      assert_match("file:///foo.rb (RubyLsp::Store::NonExistingDocumentError)", error.message)
    end
  end

  def test_semantic_highlighting_support_is_disabled_at_100k_characters
    path_to_large_file = Gem.find_files("prism/**/node.rb").first
    uri = URI::Generic.from_path(path: path_to_large_file)

    capture_io do
      @server.process_message({
        method: "textDocument/didOpen",
        params: {
          textDocument: {
            uri: uri,
            text: File.read(path_to_large_file),
            version: 1,
            languageId: "ruby",
          },
        },
      })

      @server.process_message({
        id: 1,
        method: "textDocument/semanticTokens/full",
        params: { textDocument: { uri: uri } },
      })

      result = find_message(RubyLsp::Result, id: 1)
      assert_nil(result.response)

      @server.process_message({
        id: 2,
        method: "textDocument/semanticTokens/full/delta",
        params: { textDocument: { uri: uri } },
      })

      result = find_message(RubyLsp::Result, id: 2)
      assert_nil(result.response)

      @server.process_message({
        id: 3,
        method: "textDocument/semanticTokens/range",
        params: {
          textDocument: { uri: uri },
          range: { start: { line: 0, character: 0 }, end: { line: 15, character: 0 } },
        },
      })

      result = find_message(RubyLsp::Result, id: 3)
      assert_nil(result.response)
    end
  end

  def test_inlay_hints_are_cached
    uri = URI::Generic.from_path(path: "/fake.rb")
    text = <<~RUBY
      def foo
      rescue
      end
    RUBY

    capture_io do
      @server.process_message(id: 1, method: "initialize", params: {
        initializationOptions: {
          featuresConfiguration: {
            inlayHint: {
              enableAll: true,
            },
          },
        },
      })

      @server.process_message({
        method: "textDocument/didOpen",
        params: {
          textDocument: {
            uri: uri,
            text: text,
            version: 1,
            languageId: "ruby",
          },
        },
      })

      @server.process_message({
        id: 2,
        method: "textDocument/documentSymbol",
        params: { textDocument: { uri: uri } },
      })

      result = find_message(RubyLsp::Result, id: 2)
      refute_nil(result.response)

      RubyLsp::Requests::InlayHints.any_instance.expects(:perform).never

      @server.process_message({
        id: 3,
        method: "textDocument/inlayHint",
        params: { textDocument: { uri: uri } },
      })

      result = find_message(RubyLsp::Result, id: 3)
      assert_equal(1, result.response.length)
    end
  end

  def test_show_window_responses_are_redirected_to_addons
    klass = Class.new(RubyLsp::Addon) do
      def activate(global_state, outgoing_queue)
        @activated = true
        @settings = global_state.settings_for_addon(name)
      end

      def deactivate; end

      def name
        "My Add-on"
      end

      def version
        "0.1.0"
      end

      def handle_window_show_message_response(title)
      end
    end

    begin
      @server.load_addons
      addon = RubyLsp::Addon.addons.find { |a| a.is_a?(klass) }
      addon.expects(:handle_window_show_message_response).with("hello")

      @server.process_message(result: { method: "window/showMessageRequest", title: "hello", addon_name: "My Add-on" })
    ensure
      RubyLsp::Addon.addons.clear
      RubyLsp::Addon.addon_classes.clear
    end
  end

  def test_cancelling_requests_returns_nil
    uri = URI("file:///foo.rb")

    @server.process_message({
      method: "textDocument/didOpen",
      params: {
        textDocument: {
          uri: uri,
          text: "class Foo\nend",
          version: 1,
          languageId: "ruby",
        },
      },
    })

    mutex = Mutex.new
    mutex.lock

    # Use a mutex to lock the request in the middle so that we can cancel it before it finishes
    @server.stubs(:text_document_definition) do |_message|
      mutex.synchronize { 123 }
    end

    thread = Thread.new do
      @server.push_message({
        id: 1,
        method: "textDocument/definition",
        params: {
          textDocument: {
            uri: uri,
          },
          position: { line: 0, character: 6 },
        },
      })
    end

    @server.process_message({ method: "$/cancelRequest", params: { id: 1 } })
    mutex.unlock
    thread.join

    result = find_message(RubyLsp::Result)
    assert_nil(result.response)
  end

  def test_unsaved_changes_are_indexed_when_computing_automatic_features
    uri = URI("file:///foo.rb")
    index = @server.global_state.index

    # Simulate opening a file. First, send the notification to open the file with a class inside
    @server.process_message({
      method: "textDocument/didOpen",
      params: {
        textDocument: {
          uri: uri,
          text: +"class Foo\nend",
          version: 1,
          languageId: "ruby",
        },
      },
    })
    # Fire the automatic features requests to trigger indexing
    @server.process_message({
      id: 1,
      method: "textDocument/documentSymbol",
      params: { textDocument: { uri: uri } },
    })

    entries = index["Foo"]
    assert_equal(1, entries.length)

    # Modify the file without saving
    @server.process_message({
      method: "textDocument/didChange",
      params: {
        textDocument: { uri: uri, version: 2 },
        contentChanges: [
          { text: "  def bar\n  end\n", range: { start: { line: 1, character: 0 }, end: { line: 1, character: 0 } } },
        ],
      },
    })

    # Parse the document after it was modified. This occurs automatically when we receive a text document request, to
    # avoid parsing the document multiple times, but that depends on request coming in through the STDIN pipe, which
    # isn't reproduced here. Parsing manually matches what happens normally
    store = @server.instance_variable_get(:@store)
    store.get(uri).parse!

    # Trigger the automatic features again
    @server.process_message({
      id: 2,
      method: "textDocument/documentSymbol",
      params: { textDocument: { uri: uri } },
    })

    # There should still only be one entry for each declaration, but we should have picked up the new ones
    entries = index["Foo"]
    assert_equal(1, entries.length)

    entries = index["bar"]
    assert_equal(1, entries.length)
  end

  def test_ancestors_are_recomputed_even_on_unsaved_changes
    uri = URI("file:///foo.rb")
    index = @server.global_state.index
    source = +<<~RUBY
      module Bar; end

      class Foo
        extend Bar
      end
    RUBY

    # Simulate opening a file. First, send the notification to open the file with a class inside
    @server.process_message({
      method: "textDocument/didOpen",
      params: {
        textDocument: {
          uri: uri,
          text: source,
          version: 1,
          languageId: "ruby",
        },
      },
    })
    # Fire the automatic features requests to trigger indexing
    @server.process_message({
      id: 1,
      method: "textDocument/documentSymbol",
      params: { textDocument: { uri: uri } },
    })

    assert_equal(["Foo::<Class:Foo>", "Bar"], index.linearized_ancestors_of("Foo::<Class:Foo>"))

    # Delete the extend
    @server.process_message({
      method: "textDocument/didChange",
      params: {
        textDocument: { uri: uri, version: 2 },
        contentChanges: [
          { text: "", range: { start: { line: 3, character: 0 }, end: { line: 3, character: 12 } } },
        ],
      },
    })

    # Parse the document after it was modified. This occurs automatically when we receive a text document request, to
    # avoid parsing the document multiple times, but that depends on request coming in through the STDIN pipe, which
    # isn't reproduced here. Parsing manually matches what happens normally
    store = @server.instance_variable_get(:@store)
    document = store.get(uri)

    assert_equal(<<~RUBY, document.source)
      module Bar; end

      class Foo

      end
    RUBY

    document.parse!

    # Trigger the automatic features again
    @server.process_message({
      id: 2,
      method: "textDocument/documentSymbol",
      params: { textDocument: { uri: uri } },
    })

    result = find_message(RubyLsp::Result, id: 2)
    refute_nil(result)

    assert_equal(["Foo::<Class:Foo>"], index.linearized_ancestors_of("Foo::<Class:Foo>"))
  end

  def test_edits_outside_of_declarations_do_not_trigger_indexing
    uri = URI("file:///foo.rb")
    index = @server.global_state.index

    # Simulate opening a file. First, send the notification to open the file with a class inside
    @server.process_message({
      method: "textDocument/didOpen",
      params: {
        textDocument: {
          uri: uri,
          text: +"class Foo\n\nend",
          version: 1,
          languageId: "ruby",
        },
      },
    })
    # Fire the automatic features requests to trigger indexing
    @server.process_message({
      id: 1,
      method: "textDocument/documentSymbol",
      params: { textDocument: { uri: uri } },
    })

    entries = index["Foo"]
    assert_equal(1, entries.length)

    # Modify the file without saving
    @server.process_message({
      method: "textDocument/didChange",
      params: {
        textDocument: { uri: uri, version: 2 },
        contentChanges: [
          { text: "d", range: { start: { line: 1, character: 0 }, end: { line: 1, character: 0 } } },
        ],
      },
    })

    # Parse the document after it was modified. This occurs automatically when we receive a text document request, to
    # avoid parsing the document multiple times, but that depends on request coming in through the STDIN pipe, which
    # isn't reproduced here. Parsing manually matches what happens normally
    store = @server.instance_variable_get(:@store)
    store.get(uri).parse!

    # Trigger the automatic features again
    index.expects(:delete).never
    @server.process_message({
      id: 2,
      method: "textDocument/documentSymbol",
      params: { textDocument: { uri: uri } },
    })

    entries = index["Foo"]
    assert_equal(1, entries.length)
  end

  def test_rubocop_config_changes_trigger_workspace_diagnostic_refresh
    @server.process_message({
      id: 1,
      method: "initialize",
      params: {
        initializationOptions: {},
        capabilities: {
          general: {
            positionEncodings: ["utf-8"],
          },
          workspace: { diagnostics: { refreshSupport: true } },
        },
      },
    })
    @server.global_state.index.index_all(uris: [])

    [".rubocop.yml", ".rubocop", ".rubocop_todo.yml"].each do |config_file|
      uri = URI::Generic.from_path(path: File.join(Dir.pwd, config_file))

      @server.process_message({
        method: "workspace/didChangeWatchedFiles",
        params: {
          changes: [
            {
              uri: uri,
              type: RubyLsp::Constant::FileChangeType::CHANGED,
            },
          ],
        },
      })

      request = find_message(RubyLsp::Request)
      assert_equal("workspace/diagnostic/refresh", request.method)
    end
  end

  def test_compose_bundle_creates_file_to_skip_next_compose
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        @server.process_message({
          id: 1,
          method: "initialize",
          params: {
            initializationOptions: {},
            capabilities: { general: { positionEncodings: ["utf-8"] } },
            workspaceFolders: [{ uri: URI::Generic.from_path(path: dir).to_s }],
          },
        })

        capture_subprocess_io do
          @server.send(:compose_bundle, { id: 2, method: "rubyLsp/composeBundle" })&.join
        end
        result = find_message(RubyLsp::Result, id: 2)
        assert(result.response[:success])
        assert_path_exists(File.join(dir, ".ruby-lsp", "bundle_is_composed"))
      end
    end
  end

  def test_compose_bundle_detects_syntax_errors_in_lockfile
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        @server.process_message({
          id: 1,
          method: "initialize",
          params: {
            initializationOptions: {},
            capabilities: { general: { positionEncodings: ["utf-8"] } },
            workspaceFolders: [{ uri: URI::Generic.from_path(path: dir).to_s }],
          },
        })

        File.write(File.join(dir, "Gemfile"), <<~GEMFILE)
          source "https://rubygems.org"
          gem "stringio"
        GEMFILE

        # Write a lockfile that has a git conflict marker
        lockfile_contents = <<~LOCKFILE
          GEM
            remote: https://rubygems.org/
            specs:
              <<<<<<< HEAD
              stringio (3.1.0)
              >>>>>> 12345

          PLATFORMS
            arm64-darwin-23
            ruby

          DEPENDENCIES
            stringio

          BUNDLED WITH
            2.5.7
        LOCKFILE
        File.write(File.join(dir, "Gemfile.lock"), lockfile_contents)

        capture_subprocess_io do
          @server.send(:compose_bundle, { id: 2, method: "rubyLsp/composeBundle" })&.join
        end
      end

      error = find_message(RubyLsp::Error)
      assert_match("Your Gemfile.lock contains merge conflicts.", error.message)
    end
  end

  def test_compose_bundle_does_not_fail_if_bundle_is_missing
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        @server.process_message({
          id: 1,
          method: "initialize",
          params: {
            initializationOptions: {},
            capabilities: { general: { positionEncodings: ["utf-8"] } },
            workspaceFolders: [{ uri: URI::Generic.from_path(path: dir).to_s }],
          },
        })

        capture_subprocess_io do
          @server.send(:compose_bundle, { id: 2, method: "rubyLsp/composeBundle" })&.join
        end

        result = find_message(RubyLsp::Result, id: 2)
        assert(result.response[:success])
      end
    end
  end

  def test_compose_bundle_does_not_fail_if_restarting_on_lockfile_deletion
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        @server.process_message({
          id: 1,
          method: "initialize",
          params: {
            initializationOptions: {},
            capabilities: { general: { positionEncodings: ["utf-8"] } },
            workspaceFolders: [{ uri: URI::Generic.from_path(path: dir).to_s }],
          },
        })

        File.write(File.join(dir, "Gemfile"), <<~GEMFILE)
          source "https://rubygems.org"
          gem "stringio"
        GEMFILE

        capture_subprocess_io do
          @server.send(:compose_bundle, { id: 2, method: "rubyLsp/composeBundle" })&.join
        end

        result = find_message(RubyLsp::Result, id: 2)
        assert(result.response[:success])
      end
    end
  end

  def test_does_not_index_on_did_change_watched_files_if_document_is_managed_by_client
    path = File.join(Dir.pwd, "lib", "foo.rb")
    source = <<~RUBY
      class Foo
      end
    RUBY
    File.write(path, source)
    uri = URI::Generic.from_path(path: path)

    begin
      @server.process_message({
        method: "textDocument/didOpen",
        params: {
          textDocument: {
            uri: uri,
            text: source,
            version: 1,
            languageId: "ruby",
          },
        },
      })

      @server.global_state.index.index_all(uris: [])
      @server.global_state.index.expects(:handle_change).never
      @server.process_message({
        method: "workspace/didChangeWatchedFiles",
        params: {
          changes: [
            {
              uri: uri,
              type: RubyLsp::Constant::FileChangeType::CHANGED,
            },
          ],
        },
      })

      @server.global_state.index.expects(:handle_change).once
      @server.process_message({
        method: "textDocument/documentSymbol",
        params: {
          textDocument: {
            uri: uri,
          },
        },
      })
    ensure
      FileUtils.rm(path) if File.exist?(path)
    end
  end

  def test_receiving_a_created_file_watch_notification_after_did_open_uses_handle_change
    path = File.join(Dir.pwd, "lib", "foo.rb")
    source = <<~RUBY
      class Foo
      end
    RUBY
    File.write(path, source)
    uri = URI::Generic.from_path(path: path)

    begin
      # Simulate the editor opening a document and then immediately firing a document symbol request
      @server.process_message({
        method: "textDocument/didOpen",
        params: {
          textDocument: {
            uri: uri,
            text: source,
            version: 1,
            languageId: "ruby",
          },
        },
      })
      @server.process_message({
        method: "textDocument/documentSymbol",
        params: { textDocument: { uri: uri } },
      })

      @server.global_state.index.index_all(uris: [])
      # Then send a late did change watched files notification for the creation of the file
      @server.process_message({
        method: "workspace/didChangeWatchedFiles",
        params: {
          changes: [
            {
              uri: uri,
              type: RubyLsp::Constant::FileChangeType::CREATED,
            },
          ],
        },
      })

      entries = @server.global_state.index["Foo"]
      assert_equal(1, entries&.length)

      uris = @server.global_state.index.search_require_paths("foo")
      assert_equal(["foo"], uris.map(&:require_path))
    ensure
      FileUtils.rm(path) if File.exist?(path)
    end
  end

  def test_diagnose_state
    @server.process_message({
      method: "textDocument/didOpen",
      params: {
        textDocument: {
          uri: URI::Generic.from_path(path: "/foo.rb"),
          text: "class Foo\nend",
          version: 1,
          languageId: "ruby",
        },
      },
    })
    @server.process_message({ id: 1, method: "rubyLsp/diagnoseState", params: {} })
    result = find_message(RubyLsp::Result, id: 1)

    assert(result.response[:workerAlive])
    assert_equal({ "file:///foo.rb" => "class Foo\nend" }, result.response[:documents])
    assert(result.response.key?(:backtrace))
    assert_equal(0, result.response[:incomingQueueSize])
  end

  def test_modifying_files_during_initial_indexing_does_not_duplicate_entries
    path = File.join(Dir.pwd, "lib", "foo.rb")
    uri = URI::Generic.from_path(path: path)

    begin
      @server.process_message({
        id: 1,
        method: "initialize",
        params: {
          initializationOptions: {},
          capabilities: { general: { positionEncodings: ["utf-8"] }, window: { workDoneProgress: true } },
        },
      })

      # Start indexing
      File.write(path, "class Foo\nend")
      @server.process_message({ method: "initialized", params: {} })

      # Then immediately notify that a file was modified before indexing is finished
      File.write(path, "class Foo\n  def bar\n  end\nend")
      @server.process_message({
        method: "workspace/didChangeWatchedFiles",
        params: {
          changes: [
            {
              uri: uri.to_s,
              type: RubyLsp::Constant::FileChangeType::CHANGED,
            },
          ],
        },
      })

      wait_for_indexing

      # There should not be a duplicate declaration
      index = @server.global_state.index
      assert_equal(1, index["Foo"]&.length)
    ensure
      FileUtils.rm(path)
    end
  end

  def test_requests_code_lens_refresh_after_indexing
    @server.process_message({
      id: 1,
      method: "initialize",
      params: {
        initializationOptions: {},
        capabilities: {
          general: { positionEncodings: ["utf-8"] },
          window: { workDoneProgress: true },
          workspace: { codeLens: { refreshSupport: true } },
        },
      },
    })

    @server.process_message({ method: "initialized", params: {} })

    wait_for_indexing

    request = find_message(RubyLsp::Request, "workspace/codeLens/refresh")
    refute_nil(request)
  end

  def test_busts_ancestor_cache_after_indexing
    @server.process_message({
      id: 1,
      method: "initialize",
      params: {
        initializationOptions: {},
        capabilities: { general: { positionEncodings: ["utf-8"] }, window: { workDoneProgress: true } },
      },
    })

    @server.process_message({ method: "initialized", params: {} })

    wait_for_indexing

    assert_empty(@server.global_state.index.instance_variable_get(:@ancestors))
  end

  def test_code_lens_resolve_populates_run_test_command
    arguments = ["/workspace/test/foo_test.rb", "FooTest#test_something"]
    @server.process_message({
      id: 1,
      method: "codeLens/resolve",
      params: {
        range: { start: { line: 0, character: 0 }, end: { line: 0, character: 1 } },
        data: {
          kind: "run_test",
          arguments: arguments,
        },
      },
    })

    result = find_message(RubyLsp::Result, id: 1)
    command = result.response[:command]

    assert_equal("▶ Run", command.title)
    assert_equal("rubyLsp.runTest", command.command)
    assert_equal(arguments, command.arguments)
  end

  def test_code_lens_resolve_populates_run_test_in_terminal_command
    arguments = ["/workspace/test/foo_test.rb", "FooTest#test_something"]
    @server.process_message({
      id: 1,
      method: "codeLens/resolve",
      params: {
        range: { start: { line: 0, character: 0 }, end: { line: 0, character: 1 } },
        data: {
          kind: "run_test_in_terminal",
          arguments: arguments,
        },
      },
    })

    result = find_message(RubyLsp::Result, id: 1)
    command = result.response[:command]

    assert_equal("▶ Run in terminal", command.title)
    assert_equal("rubyLsp.runTestInTerminal", command.command)
    assert_equal(arguments, command.arguments)
  end

  def test_code_lens_resolve_populates_debug_test_command
    arguments = ["/workspace/test/foo_test.rb", "FooTest#test_something"]
    @server.process_message({
      id: 1,
      method: "codeLens/resolve",
      params: {
        range: { start: { line: 0, character: 0 }, end: { line: 0, character: 1 } },
        data: {
          kind: "debug_test",
          arguments: arguments,
        },
      },
    })

    result = find_message(RubyLsp::Result, id: 1)
    command = result.response[:command]

    assert_equal("⚙ Debug", command.title)
    assert_equal("rubyLsp.debugTest", command.command)
    assert_equal(arguments, command.arguments)
  end

  def test_code_lens_caches_discovered_tests
    uri = URI::Generic.from_path(path: "/foo.rb")
    text = <<~RUBY
      class MyTest < Minitest::Test
        def test_something
        end
      end
    RUBY

    @server.process_message({
      method: "textDocument/didOpen",
      params: {
        textDocument: {
          uri: uri,
          text: text,
          version: 1,
          languageId: "ruby",
        },
      },
    })

    @server.process_message({
      id: 1,
      method: "textDocument/codeLens",
      params: {
        textDocument: { uri: uri },
      },
    })

    result = find_message(RubyLsp::Result, id: 1)
    assert_equal(6, result.response.length)

    RubyLsp::Requests::DiscoverTests.any_instance.expects(:perform).never
    @server.process_message({
      id: 2,
      method: "rubyLsp/discoverTests",
      params: {
        textDocument: { uri: uri },
      },
    })
  end

  def test_addons_are_unable_to_exit_the_server_process
    Class.new(RubyLsp::Addon) do
      def activate(global_state, outgoing_queue); end

      def workspace_did_change_watched_files(changes)
        exit
      end

      def name
        "Bad add-on"
      end

      def deactivate; end

      def version
        "0.1.0"
      end
    end

    @server.load_addons

    begin
      @server.global_state.index.index_all(uris: [])
      @server.process_message({
        method: "workspace/didChangeWatchedFiles",
        params: {
          changes: [
            {
              uri: URI::Generic.from_path(path: File.join(Dir.pwd, "lib", "server.rb")).to_s,
              type: RubyLsp::Constant::FileChangeType::CHANGED,
            },
          ],
        },
      })
      pass
    rescue SystemExit
      flunk("Add-on was able to exit the server process")
    ensure
      RubyLsp::Addon.unload_addons
    end
  end

  def test_invalid_location_errors_are_not_reported_to_telemetry
    uri = URI::Generic.from_path(path: "/foo.rb")

    @server.process_message({
      method: "textDocument/didOpen",
      params: {
        textDocument: {
          uri: uri,
          text: "class Foo\nend",
          version: 1,
          languageId: "ruby",
        },
      },
    })

    @server.push_message({
      id: 1,
      method: "textDocument/definition",
      params: {
        textDocument: {
          uri: uri,
        },
        position: { line: 10, character: 6 },
      },
    })

    error = find_message(RubyLsp::Error)
    attributes = error.to_hash[:error]
    assert_nil(attributes[:data])
    assert_match("Document::InvalidLocationError", attributes[:message])
  end

  private

  def wait_for_indexing
    message = @server.pop_response
    until message.is_a?(RubyLsp::Notification) && message.method == "$/progress" &&
        message.params #: as untyped
            .value.kind == "end"
      message = @server.pop_response
    end
  end

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

      def version
        "0.1.0"
      end
    end

    Class.new(RubyLsp::Addon) do
      def activate(global_state, outgoing_queue)
        # simulates failed add-on activation
        raise "boom"
      end

      def name
        "Bar"
      end

      def deactivate; end
    end
  end

  #: (Class desired_class, ?String? desired_method, ?id: Integer?) -> untyped
  def find_message(desired_class, desired_method = nil, id: nil)
    message = @server.pop_response

    until message.is_a?(desired_class) && (!desired_method || message.method == desired_method) &&
        (!id || message.id == id)
      message = @server.pop_response

      if message.is_a?(RubyLsp::Error) && desired_class != RubyLsp::Error
        flunk("Unexpected error: #{message.message}")
      end
    end

    message
  end
end
