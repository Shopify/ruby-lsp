# typed: true
# frozen_string_literal: true

require "test_helper"

class ScopeTest < Minitest::Test
  def test_finding_parameter_in_immediate_scope
    scope = RubyLsp::Scope.new
    scope.add("foo", :parameter)

    assert_equal(:parameter, T.must(scope.lookup("foo")).type)
  end

  def test_finding_parameter_in_parent_scope
    parent = RubyLsp::Scope.new
    parent.add("foo", :parameter)

    scope = RubyLsp::Scope.new(parent)
    assert_equal(:parameter, T.must(scope.lookup("foo")).type)
  end

  def test_not_finding_parameter
    scope = RubyLsp::Scope.new
    refute(scope.lookup("foo"))
  end
end
