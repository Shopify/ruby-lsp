# typed: true
# frozen_string_literal: true

require "test_helper"

class ScopeTest < Minitest::Test
  def test_finding_parameter_in_immediate_scope
    scope = RubyLsp::Scope.new
    scope.add("foo")

    assert(scope.parameter?("foo"))
  end

  def test_finding_parameter_in_parent_scope
    parent = RubyLsp::Scope.new
    parent.add("foo")

    scope = RubyLsp::Scope.new(parent)

    assert(scope.parameter?("foo"))
  end

  def test_not_finding_parameter
    scope = RubyLsp::Scope.new
    refute(scope.parameter?("foo"))
  end
end
