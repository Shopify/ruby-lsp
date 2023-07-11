# typed: true
# frozen_string_literal: true

require "test_helper"

class ExecutorTest < Minitest::Test
  def setup
    @store = RubyLsp::Store.new
    @message_queue = Thread::Queue.new
    @executor = RubyLsp::Executor.new(@store, @message_queue)
  end

  def teardown
    @message_queue.close
  end

  def test_initialize_enabled_features_with_array
    response = @executor.execute({
      method: "initialize",
      params: {
        initializationOptions: { enabledFeatures: ["semanticHighlighting"] },
        capabilities: { general: { positionEncodings: ["utf-8"] } },
      },
    }).response

    hash = JSON.parse(response.to_json)
    capabilities = hash["capabilities"]

    # TextSynchronization + encodings + semanticHighlighting
    assert_equal(3, capabilities.length)
    assert_includes(capabilities, "semanticTokensProvider")
  end

  def test_initialize_enabled_features_with_hash
    response = @executor.execute({
      method: "initialize",
      params: {
        initializationOptions: { enabledFeatures: { "semanticHighlighting" => false } },
        capabilities: { general: { positionEncodings: ["utf-8"] } },
      },
    }).response

    hash = JSON.parse(response.to_json)
    capabilities = hash["capabilities"]

    # Only semantic highlighting is turned off because all others default to true when configuring with a hash
    refute_includes(capabilities, "semanticTokensProvider")
  end

  def test_initialize_enabled_features_with_no_configuration
    response = @executor.execute({
      method: "initialize",
      params: {
        initializationOptions: {},
        capabilities: { general: { positionEncodings: ["utf-8"] } },
      },
    }).response

    hash = JSON.parse(response.to_json)
    capabilities = hash["capabilities"]

    # All features are enabled by default
    assert_includes(capabilities, "semanticTokensProvider")
  end

  def test_initialize_defaults_to_utf_8_if_present
    response = @executor.execute({
      method: "initialize",
      params: {
        initializationOptions: {},
        capabilities: { general: { positionEncodings: ["utf-8", "utf-16"] } },
      },
    }).response

    hash = JSON.parse(response.to_json)

    # All features are enabled by default
    assert_includes("utf-8", hash.dig("capabilities", "positionEncoding"))
  end

  def test_initialize_uses_utf_16_if_utf_8_is_not_present
    response = @executor.execute({
      method: "initialize",
      params: {
        initializationOptions: {},
        capabilities: { general: { positionEncodings: ["utf-16"] } },
      },
    }).response

    hash = JSON.parse(response.to_json)

    # All features are enabled by default
    assert_includes("utf-16", hash.dig("capabilities", "positionEncoding"))
  end

  def test_initialize_uses_utf_16_if_no_encodings_are_specified
    response = @executor.execute({
      method: "initialize",
      params: {
        initializationOptions: {},
        capabilities: { general: { positionEncodings: [] } },
      },
    }).response

    hash = JSON.parse(response.to_json)

    # All features are enabled by default
    assert_includes("utf-16", hash.dig("capabilities", "positionEncoding"))
  end

  def test_rubocop_errors_push_window_notification
    @executor.expects(:formatting).raises(StandardError, "boom").once

    @executor.execute({
      method: "textDocument/formatting",
      params: {
        textDocument: { uri: "file:///foo.rb" },
      },
    })

    notification = T.must(@message_queue.pop)
    assert_equal("window/showMessage", notification.message)
    assert_equal(
      "Formatting error: boom",
      T.cast(notification.params, RubyLsp::Interface::ShowMessageParams).message,
    )
  end

  def test_did_close_clears_diagnostics
    @store.set(uri: "file:///foo.rb", source: "", version: 1)
    @executor.execute({
      method: "textDocument/didClose",
      params: {
        textDocument: { uri: "file:///foo.rb" },
      },
    })

    notification = T.must(@message_queue.pop)
    assert_equal("textDocument/publishDiagnostics", notification.message)
    assert_empty(T.cast(notification.params, RubyLsp::Interface::PublishDiagnosticsParams).diagnostics)
  ensure
    @store.delete("file:///foo.rb")
  end

  def test_detects_rubocop_if_direct_dependency
    stub_dependencies(rubocop: true, syntax_tree: false)
    RubyLsp::Executor.new(@store, @message_queue)
      .execute(method: "initialize", params: { initializationOptions: { formatter: "auto" } })
    assert_equal("rubocop", @store.formatter)
  end

  def test_detects_syntax_tree_if_direct_dependency
    stub_dependencies(rubocop: false, syntax_tree: true)
    RubyLsp::Executor.new(@store, @message_queue)
      .execute(method: "initialize", params: { initializationOptions: { formatter: "auto" } })
    assert_equal("syntax_tree", @store.formatter)
  end

  def test_gives_rubocop_precedence_if_syntax_tree_also_present
    stub_dependencies(rubocop: true, syntax_tree: true)
    RubyLsp::Executor.new(@store, @message_queue).send(
      :initialize_request,
      { initializationOptions: { formatter: "auto" } },
    )
    assert_equal("rubocop", @store.formatter)
  end

  def test_sets_formatter_to_none_if_neither_rubocop_or_syntax_tree_are_present
    stub_dependencies(rubocop: false, syntax_tree: false)
    RubyLsp::Executor.new(@store, @message_queue).send(
      :initialize_request,
      { initializationOptions: { formatter: "auto" } },
    )
    assert_equal("none", @store.formatter)
  end

  def test_shows_error_if_formatter_set_to_rubocop_but_rubocop_not_available
    with_uninstalled_rubocop do
      executor = RubyLsp::Executor.new(@store, @message_queue)

      executor.execute(method: "initialize", params: { initializationOptions: { formatter: "rubocop" } })
      executor.execute(method: "initialized")

      assert_equal("none", @store.formatter)
      refute_empty(@message_queue)
      notification = T.must(@message_queue.pop)
      assert_equal("window/showMessage", notification.message)
      assert_equal(
        "Ruby LSP formatter is set to `rubocop` but RuboCop was not found in the Gemfile or gemspec.",
        T.cast(notification.params, RubyLsp::Interface::ShowMessageParams).message,
      )
    end
  end

  def test_registered_extensions_returns_name_and_errors
    Class.new(RubyLsp::Extension) do
      attr_reader :activated

      def activate
      end

      def name
        "My extension"
      end
    end

    RubyLsp::Extension.load_extensions({})
    response = @executor.execute({ method: "rubyLsp/workspace/registeredExtensions" }).response

    begin
      assert_includes(response, { name: "My extension", errors: [] })
    ensure
      RubyLsp::Extension.extensions.clear
    end
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
    dependencies = {}
    dependencies["syntax_tree"] = "..." if syntax_tree
    dependencies["rubocop"] = "..." if rubocop
    Bundler.locked_gems.stubs(:dependencies).returns(dependencies)
  end
end
