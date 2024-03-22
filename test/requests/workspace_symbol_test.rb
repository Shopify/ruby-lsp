# typed: true
# frozen_string_literal: true

require "test_helper"

class WorkspaceSymbolTest < Minitest::Test
  def setup
    @global_state = RubyLsp::GlobalState.new
    @global_state.stubs(:typechecker).returns(false)
    @index = @global_state.index
  end

  def test_returns_index_entries_based_on_query
    @index.index_single(RubyIndexer::IndexablePath.new(nil, "/fake.rb"), <<~RUBY)
      class Foo; end
      module Bar; end

      CONSTANT = 1
    RUBY

    result = RubyLsp::Requests::WorkspaceSymbol.new(@global_state, "Foo").perform.first
    assert_equal("Foo", T.must(result).name)
    assert_equal(RubyLsp::Constant::SymbolKind::CLASS, T.must(result).kind)

    result = RubyLsp::Requests::WorkspaceSymbol.new(@global_state, "Bar").perform.first
    assert_equal("Bar", T.must(result).name)
    assert_equal(RubyLsp::Constant::SymbolKind::NAMESPACE, T.must(result).kind)

    result = RubyLsp::Requests::WorkspaceSymbol.new(@global_state, "CONST").perform.first
    assert_equal("CONSTANT", T.must(result).name)
    assert_equal(RubyLsp::Constant::SymbolKind::CONSTANT, T.must(result).kind)
  end

  def test_fuzzy_matches_symbols
    @index.index_single(RubyIndexer::IndexablePath.new(nil, "/fake.rb"), <<~RUBY)
      class Foo; end
      module Bar; end

      CONSTANT = 1
    RUBY

    result = RubyLsp::Requests::WorkspaceSymbol.new(@global_state, "Floo").perform.first
    assert_equal("Foo", T.must(result).name)
    assert_equal(RubyLsp::Constant::SymbolKind::CLASS, T.must(result).kind)

    result = RubyLsp::Requests::WorkspaceSymbol.new(@global_state, "Bear").perform.first
    assert_equal("Bar", T.must(result).name)
    assert_equal(RubyLsp::Constant::SymbolKind::NAMESPACE, T.must(result).kind)

    result = RubyLsp::Requests::WorkspaceSymbol.new(@global_state, "CONF").perform.first
    assert_equal("CONSTANT", T.must(result).name)
    assert_equal(RubyLsp::Constant::SymbolKind::CONSTANT, T.must(result).kind)
  end

  def test_matches_only_gem_symbols_if_typechecker_is_present
    # create a new global state so the stub is not used
    @global_state = RubyLsp::GlobalState.new
    @index = @global_state.index
    indexable = RubyIndexer::IndexablePath.new(nil, "#{Dir.pwd}/workspace_symbol_foo.rb")

    @index.index_single(indexable, <<~RUBY)
      class Foo; end
    RUBY

    path = "#{Bundler.bundle_path}/gems/fake-gem-0.1.0/lib/gem_symbol_foo.rb"
    @index.index_single(RubyIndexer::IndexablePath.new(nil, path), <<~RUBY)
      class Foo; end
    RUBY

    result = RubyLsp::Requests::WorkspaceSymbol.new(@global_state, "Foo").perform
    assert_equal(1, result.length)
    assert_equal(URI::Generic.from_path(path: path).to_s, T.must(result.first).location.uri)
  end

  def test_symbols_include_container_name
    @index.index_single(RubyIndexer::IndexablePath.new(nil, "/fake.rb"), <<~RUBY)
      module Foo
        class Bar; end
      end
    RUBY

    result = RubyLsp::Requests::WorkspaceSymbol.new(@global_state, "Foo::Bar").perform.first
    assert_equal("Foo::Bar", T.must(result).name)
    assert_equal(RubyLsp::Constant::SymbolKind::CLASS, T.must(result).kind)
    assert_equal("Foo", T.must(result).container_name)
  end

  def test_finds_default_gem_symbols
    @index.index_single(RubyIndexer::IndexablePath.new(nil, "#{RbConfig::CONFIG["rubylibdir"]}/pathname.rb"))

    result = RubyLsp::Requests::WorkspaceSymbol.new(@global_state, "Pathname").perform
    refute_empty(result)
  end

  def test_does_not_include_private_constants
    @index.index_single(RubyIndexer::IndexablePath.new(nil, "/fake.rb"), <<~RUBY)
      class Foo
        CONSTANT = 1
        private_constant(:CONSTANT)
      end
    RUBY

    result = RubyLsp::Requests::WorkspaceSymbol.new(@global_state, "Foo::CONSTANT").perform
    assert_equal(1, result.length)
    assert_equal("Foo", T.must(result.first).name)
  end

  def test_returns_method_symbols
    @index.index_single(RubyIndexer::IndexablePath.new(nil, "/fake.rb"), <<~RUBY)
      class Foo
        attr_reader :baz

        def initialize; end
        def bar; end
      end
    RUBY

    result = RubyLsp::Requests::WorkspaceSymbol.new(@global_state, "bar").perform.first
    assert_equal("bar", T.must(result).name)
    assert_equal(RubyLsp::Constant::SymbolKind::METHOD, T.must(result).kind)

    result = RubyLsp::Requests::WorkspaceSymbol.new(@global_state, "initialize").perform.first
    assert_equal("initialize", T.must(result).name)
    assert_equal(RubyLsp::Constant::SymbolKind::CONSTRUCTOR, T.must(result).kind)

    result = RubyLsp::Requests::WorkspaceSymbol.new(@global_state, "baz").perform.first
    assert_equal("baz", T.must(result).name)
    assert_equal(RubyLsp::Constant::SymbolKind::PROPERTY, T.must(result).kind)
  end
end
