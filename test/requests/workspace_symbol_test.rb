# typed: true
# frozen_string_literal: true

require "test_helper"

class WorkspaceSymbolTest < Minitest::Test
  def setup
    stub_no_typechecker
    @index = RubyIndexer::Index.new
  end

  def test_returns_index_entries_based_on_query
    @index.index_single(RubyIndexer::IndexablePath.new(nil, "/fake.rb"), <<~RUBY)
      class Foo; end
      module Bar; end

      CONSTANT = 1
    RUBY

    result = RubyLsp::Requests::WorkspaceSymbol.new("Foo", @index).response.first
    assert_equal("Foo", T.must(result).name)
    assert_equal(RubyLsp::Constant::SymbolKind::CLASS, T.must(result).kind)

    result = RubyLsp::Requests::WorkspaceSymbol.new("Bar", @index).response.first
    assert_equal("Bar", T.must(result).name)
    assert_equal(RubyLsp::Constant::SymbolKind::NAMESPACE, T.must(result).kind)

    result = RubyLsp::Requests::WorkspaceSymbol.new("CONST", @index).response.first
    assert_equal("CONSTANT", T.must(result).name)
    assert_equal(RubyLsp::Constant::SymbolKind::CONSTANT, T.must(result).kind)
  end

  def test_fuzzy_matches_symbols
    @index.index_single(RubyIndexer::IndexablePath.new(nil, "/fake.rb"), <<~RUBY)
      class Foo; end
      module Bar; end

      CONSTANT = 1
    RUBY

    result = RubyLsp::Requests::WorkspaceSymbol.new("Floo", @index).response.first
    assert_equal("Foo", T.must(result).name)
    assert_equal(RubyLsp::Constant::SymbolKind::CLASS, T.must(result).kind)

    result = RubyLsp::Requests::WorkspaceSymbol.new("Bear", @index).response.first
    assert_equal("Bar", T.must(result).name)
    assert_equal(RubyLsp::Constant::SymbolKind::NAMESPACE, T.must(result).kind)

    result = RubyLsp::Requests::WorkspaceSymbol.new("CONF", @index).response.first
    assert_equal("CONSTANT", T.must(result).name)
    assert_equal(RubyLsp::Constant::SymbolKind::CONSTANT, T.must(result).kind)
  end

  def test_matches_only_gem_symbols_if_typechecker_is_present
    # reset the singleton so that the stub is not used
    Singleton.__init__(RubyLsp::DependencyDetector)
    indexable = RubyIndexer::IndexablePath.new(nil, "#{Dir.pwd}/workspace_symbol_foo.rb")

    @index.index_single(indexable, <<~RUBY)
      class Foo; end
    RUBY

    path = "#{Bundler.bundle_path}/gems/fake-gem-0.1.0/lib/gem_symbol_foo.rb"
    @index.index_single(RubyIndexer::IndexablePath.new(nil, path), <<~RUBY)
      class Foo; end
    RUBY

    result = RubyLsp::Requests::WorkspaceSymbol.new("Foo", @index).response
    assert_equal(1, result.length)
    assert_equal(URI::Generic.from_path(path: path).to_s, T.must(result.first).location.uri)
  end

  def test_symbols_include_container_name
    @index.index_single(RubyIndexer::IndexablePath.new(nil, "/fake.rb"), <<~RUBY)
      module Foo
        class Bar; end
      end
    RUBY

    result = RubyLsp::Requests::WorkspaceSymbol.new("Foo::Bar", @index).response.first
    assert_equal("Foo::Bar", T.must(result).name)
    assert_equal(RubyLsp::Constant::SymbolKind::CLASS, T.must(result).kind)
    assert_equal("Foo", T.must(result).container_name)
  end

  def test_finds_default_gem_symbols
    @index.index_single(RubyIndexer::IndexablePath.new(nil, "#{RbConfig::CONFIG["rubylibdir"]}/pathname.rb"))

    result = RubyLsp::Requests::WorkspaceSymbol.new("Pathname", @index).response
    refute_empty(result)
  end

  def test_does_not_include_private_constants
    @index.index_single(RubyIndexer::IndexablePath.new(nil, "/fake.rb"), <<~RUBY)
      class Foo
        CONSTANT = 1
        private_constant(:CONSTANT)
      end
    RUBY

    result = RubyLsp::Requests::WorkspaceSymbol.new("Foo::CONSTANT", @index).response
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

    result = RubyLsp::Requests::WorkspaceSymbol.new("bar", @index).response.first
    assert_equal("bar", T.must(result).name)
    assert_equal(RubyLsp::Constant::SymbolKind::METHOD, T.must(result).kind)

    result = RubyLsp::Requests::WorkspaceSymbol.new("initialize", @index).response.first
    assert_equal("initialize", T.must(result).name)
    assert_equal(RubyLsp::Constant::SymbolKind::CONSTRUCTOR, T.must(result).kind)

    result = RubyLsp::Requests::WorkspaceSymbol.new("baz", @index).response.first
    assert_equal("baz", T.must(result).name)
    assert_equal(RubyLsp::Constant::SymbolKind::PROPERTY, T.must(result).kind)
  end
end