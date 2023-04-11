# typed: true
# frozen_string_literal: true

require "test_helper"

class ExecutorTest < Minitest::Test
  def setup
    store = RubyLsp::Store.new
    @executor = RubyLsp::Executor.new(store)
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
end
