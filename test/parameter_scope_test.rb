# typed: true
# frozen_string_literal: true

require "test_helper"

class ParameterScopeTest < Minitest::Test
  def test_finding_parameter_in_immediate_scope
    scope = RubyLsp::ParameterScope.new
    scope << "foo"

    assert(scope.parameter?("foo"))
  end

  def test_finding_parameter_in_parent_scope
    parent = RubyLsp::ParameterScope.new
    parent << "foo"

    scope = RubyLsp::ParameterScope.new(parent)

    assert(scope.parameter?("foo"))
  end

  def test_not_finding_parameter
    scope = RubyLsp::ParameterScope.new
    refute(scope.parameter?("foo"))
  end
end
