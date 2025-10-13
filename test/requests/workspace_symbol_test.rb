# typed: true
# frozen_string_literal: true

require "test_helper"

class WorkspaceSymbolTest < Minitest::Test
  def setup
    @global_state = RubyLsp::GlobalState.new
    @global_state.stubs(:has_type_checker).returns(false)
    @index = @global_state.index
  end

  def test_returns_index_entries_based_on_query
    @index.index_single(URI::Generic.from_path(path: "/fake.rb"), <<~RUBY)
      class Foo; end
      module Bar; end

      CONSTANT = 1
    RUBY

    result = RubyLsp::Requests::WorkspaceSymbol.new(@global_state, "Foo").perform.first
    assert_equal("Foo", result&.name)
    assert_equal(RubyLsp::Constant::SymbolKind::CLASS, result&.kind)

    result = RubyLsp::Requests::WorkspaceSymbol.new(@global_state, "Bar").perform.first
    assert_equal("Bar", result&.name)
    assert_equal(RubyLsp::Constant::SymbolKind::NAMESPACE, result&.kind)

    result = RubyLsp::Requests::WorkspaceSymbol.new(@global_state, "CONST").perform.first
    assert_equal("CONSTANT", result&.name)
    assert_equal(RubyLsp::Constant::SymbolKind::CONSTANT, result&.kind)
  end

  def test_fuzzy_matches_symbols
    @index.index_single(URI::Generic.from_path(path: "/fake.rb"), <<~RUBY)
      class Foo; end
      module Bar; end

      CONSTANT = 1
    RUBY

    result = RubyLsp::Requests::WorkspaceSymbol.new(@global_state, "Floo").perform.first
    assert_equal("Foo", result&.name)
    assert_equal(RubyLsp::Constant::SymbolKind::CLASS, result&.kind)

    result = RubyLsp::Requests::WorkspaceSymbol.new(@global_state, "Bear").perform.first
    assert_equal("Bar", result&.name)
    assert_equal(RubyLsp::Constant::SymbolKind::NAMESPACE, result&.kind)

    result = RubyLsp::Requests::WorkspaceSymbol.new(@global_state, "CONF").perform.first
    assert_equal("CONSTANT", result&.name)
    assert_equal(RubyLsp::Constant::SymbolKind::CONSTANT, result&.kind)
  end

  def test_symbols_include_container_name
    @index.index_single(URI::Generic.from_path(path: "/fake.rb"), <<~RUBY)
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
    @index.index_file(URI::Generic.from_path(path: "#{RbConfig::CONFIG["rubylibdir"]}/pathname.rb"))

    result = RubyLsp::Requests::WorkspaceSymbol.new(@global_state, "Pathname").perform
    assert_empty(result)
  end

  def test_does_not_include_private_constants
    @index.index_single(URI::Generic.from_path(path: "/fake.rb"), <<~RUBY)
      class Foo
        CONSTANT = 1
        private_constant(:CONSTANT)
      end
    RUBY

    result = RubyLsp::Requests::WorkspaceSymbol.new(@global_state, "Foo::CONSTANT").perform
    assert_equal(1, result.length)
    assert_equal("Foo", result.first&.name)
  end

  def test_returns_method_symbols
    @index.index_single(URI::Generic.from_path(path: "/fake.rb"), <<~RUBY)
      class Foo
        attr_reader :baz

        def initialize; end
        def bar; end
      end
    RUBY

    result = RubyLsp::Requests::WorkspaceSymbol.new(@global_state, "bar").perform.first
    assert_equal("bar", result&.name)
    assert_equal(RubyLsp::Constant::SymbolKind::METHOD, result&.kind)

    result = RubyLsp::Requests::WorkspaceSymbol.new(@global_state, "initialize").perform.first
    assert_equal("initialize", result&.name)
    assert_equal(RubyLsp::Constant::SymbolKind::CONSTRUCTOR, result&.kind)

    result = RubyLsp::Requests::WorkspaceSymbol.new(@global_state, "baz").perform.first
    assert_equal("baz", result&.name)
    assert_equal(RubyLsp::Constant::SymbolKind::PROPERTY, result&.kind)
  end

  def test_returns_resolved_method_alias
    @index.index_single(URI::Generic.from_path(path: "/fake.rb"), <<~RUBY)
      class Foo
        def test
        end
        alias whatever test
        alias_method :bar, :to_a
        alias_method "baz", "to_a"
      end
    RUBY

    result = RubyLsp::Requests::WorkspaceSymbol.new(@global_state, "whatever").perform.first
    assert_equal("whatever", result&.name)
    assert_equal(RubyLsp::Constant::SymbolKind::METHOD, result&.kind)

    result = RubyLsp::Requests::WorkspaceSymbol.new(@global_state, "bar").perform
    assert_empty(result)

    result = RubyLsp::Requests::WorkspaceSymbol.new(@global_state, "bag").perform
    assert_empty(result)
  end

  def test_returns_resolved_constant_alias
    @index.index_single(URI::Generic.from_path(path: "/fake.rb"), <<~RUBY)
      OK = 'OK'
      class Foo
        BOK = OK
        BAD = AD
      end
    RUBY

    result = RubyLsp::Requests::WorkspaceSymbol.new(@global_state, "OK").perform.first
    assert_equal("OK", result&.name)
    assert_equal(RubyLsp::Constant::SymbolKind::CONSTANT, result&.kind)

    result = RubyLsp::Requests::WorkspaceSymbol.new(@global_state, "Foo::OK").perform.first
    assert_equal("Foo::BOK", result&.name)
    assert_equal(RubyLsp::Constant::SymbolKind::CONSTANT, result&.kind)

    result = RubyLsp::Requests::WorkspaceSymbol.new(@global_state, "BAD").perform
    assert_empty(result)
  end

  def test_returns_class_variable
    @index.index_single(URI::Generic.from_path(path: "/fake.rb"), <<~RUBY)
      class Foo
        @@test = '123'
      end
    RUBY

    result = RubyLsp::Requests::WorkspaceSymbol.new(@global_state, "test").perform.first
    assert_equal("@@test", result&.name)
    assert_equal(RubyLsp::Constant::SymbolKind::FIELD, result&.kind)
  end

  def test_returns_symbols_from_unsaved_files
    @index.index_single(URI("untitled:Untitled-1"), <<~RUBY)
      class Foo; end
    RUBY

    result = RubyLsp::Requests::WorkspaceSymbol.new(@global_state, "Foo").perform.first
    assert_equal("Foo", result&.name)
    assert_equal(RubyLsp::Constant::SymbolKind::CLASS, result&.kind)
  end
end
