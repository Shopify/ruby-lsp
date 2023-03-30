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
        capabilities: { general: { positionEncodings: "utf-8" } },
      },
    }).response

    hash = JSON.parse(response.to_json)
    capabitilies = hash["capabilities"]

    # TextSynchronization + semanticHighlighting
    assert_equal(2, capabitilies.length)
    assert_includes(capabitilies, "semanticTokensProvider")
  end

  def test_initialize_enabled_features_with_hash
    response = @executor.execute({
      method: "initialize",
      params: {
        initializationOptions: { enabledFeatures: { "semanticHighlighting" => false } },
        capabilities: { general: { positionEncodings: "utf-8" } },
      },
    }).response

    hash = JSON.parse(response.to_json)
    capabitilies = hash["capabilities"]

    # Only semantic highlighting is turned off because all others default to true when configuring with a hash
    refute_includes(capabitilies, "semanticTokensProvider")
  end

  def test_initialize_enabled_features_with_no_configuration
    response = @executor.execute({
      method: "initialize",
      params: {
        initializationOptions: {},
        capabilities: { general: { positionEncodings: "utf-8" } },
      },
    }).response

    hash = JSON.parse(response.to_json)
    capabitilies = hash["capabilities"]

    # All features are enabled by default
    assert_includes(capabitilies, "semanticTokensProvider")
  end
end
