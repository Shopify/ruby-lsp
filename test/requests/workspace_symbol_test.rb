# typed: true
# frozen_string_literal: true

require "test_helper"

class WorkspaceSymbolTest < Minitest::Test
  def setup
    @global_state = RubyLsp::GlobalState.new
    @global_state.stubs(:has_type_checker).returns(false)
    @graph = @global_state.graph
  end

  def test_returns_index_entries_based_on_query
    index_source(<<~RUBY)
      class Foo; end
      module Bar; end

      CONSTANT = 1
    RUBY

    result = RubyLsp::Requests::WorkspaceSymbol.new(@global_state, "Fo").perform.first
    assert_equal("Foo", result&.name)
    assert_equal(RubyLsp::Constant::SymbolKind::CLASS, result&.kind)

    result = RubyLsp::Requests::WorkspaceSymbol.new(@global_state, "Bar").perform.first
    assert_equal("Bar", result&.name)
    assert_equal(RubyLsp::Constant::SymbolKind::NAMESPACE, result&.kind)

    result = RubyLsp::Requests::WorkspaceSymbol.new(@global_state, "CONST").perform.first
    assert_equal("CONSTANT", result&.name)
    assert_equal(RubyLsp::Constant::SymbolKind::CONSTANT, result&.kind)
  end

  def test_symbols_include_container_name
    index_source(<<~RUBY)
      module Foo
        class Bar; end
      end
    RUBY

    result = RubyLsp::Requests::WorkspaceSymbol.new(@global_state, "Foo::Bar").perform.first
    assert_equal("Foo::Bar", result&.name)
    assert_equal(RubyLsp::Constant::SymbolKind::CLASS, result&.kind)
    assert_equal("Foo", result&.container_name)
  end

  def test_does_not_include_symbols_from_dependencies
    @graph.index_all(["#{RbConfig::CONFIG["rubylibdir"]}/pathname.rb"])
    @graph.resolve

    result = RubyLsp::Requests::WorkspaceSymbol.new(@global_state, "Pathname").perform
    assert_empty(result)
  end

  def test_includes_private_and_protected_symbols
    index_source(<<~RUBY)
      class Foo
        CONSTANT = 1
        private_constant(:CONSTANT)

        private

        def secret; end

        protected

        def internal; end
      end
    RUBY

    result = RubyLsp::Requests::WorkspaceSymbol.new(@global_state, "Foo::CONSTANT").perform.first
    assert_equal("Foo::CONSTANT", result&.name)
    assert_equal(RubyLsp::Constant::SymbolKind::CONSTANT, result&.kind)

    result = RubyLsp::Requests::WorkspaceSymbol.new(@global_state, "Foo#secret").perform.first
    assert_equal("Foo#secret()", result&.name)
    assert_equal(RubyLsp::Constant::SymbolKind::METHOD, result&.kind)

    result = RubyLsp::Requests::WorkspaceSymbol.new(@global_state, "Foo#internal").perform.first
    assert_equal("Foo#internal()", result&.name)
    assert_equal(RubyLsp::Constant::SymbolKind::METHOD, result&.kind)
  end

  def test_returns_method_symbols
    index_source(<<~RUBY)
      class Foo
        attr_reader :baz

        def initialize; end
        def bar; end
      end
    RUBY

    result = RubyLsp::Requests::WorkspaceSymbol.new(@global_state, "Foo#bar").perform.first
    assert_equal("Foo#bar()", result&.name)
    assert_equal(RubyLsp::Constant::SymbolKind::METHOD, result&.kind)

    result = RubyLsp::Requests::WorkspaceSymbol.new(@global_state, "Foo#initialize").perform.first
    assert_equal("Foo#initialize()", result&.name)
    assert_equal(RubyLsp::Constant::SymbolKind::CONSTRUCTOR, result&.kind)

    result = RubyLsp::Requests::WorkspaceSymbol.new(@global_state, "Foo#baz").perform.first
    assert_equal("Foo#baz()", result&.name)
    assert_equal(RubyLsp::Constant::SymbolKind::PROPERTY, result&.kind)
  end

  def test_returns_symbols_from_unsaved_files
    @graph.index_source("untitled:Untitled-1", <<~RUBY, "ruby")
      class Foo; end
    RUBY
    @graph.resolve

    result = RubyLsp::Requests::WorkspaceSymbol.new(@global_state, "Foo").perform.first
    assert_equal("Foo", result&.name)
    assert_equal(RubyLsp::Constant::SymbolKind::CLASS, result&.kind)
  end

  private

  #: (String, ?uri: String) -> void
  def index_source(source, uri: URI::Generic.from_path(path: "/fake.rb").to_s)
    @graph.index_source(uri, source, "ruby")
    @graph.resolve
  end
end
