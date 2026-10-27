# typed: true
# frozen_string_literal: true

require "test_helper"

class GemspecTest < Minitest::Test
  def test_declares_bundler_as_a_runtime_dependency
    spec = Gem::Specification.load(File.expand_path("../ruby-lsp.gemspec", __dir__))

    assert_includes(spec.runtime_dependencies.map(&:name), "bundler")
  end
end
