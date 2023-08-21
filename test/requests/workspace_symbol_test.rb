# typed: true
# frozen_string_literal: true

require "test_helper"

class WorkspaceSymbolTest < Minitest::Test
  def setup
    RubyLsp::DependencyDetector.const_set(:HAS_TYPECHECKER, false)
    @index = RubyIndexer::Index.new
  end

  def teardown
    RubyLsp::DependencyDetector.const_set(:HAS_TYPECHECKER, true)
  end

  def test_returns_index_entries_based_on_query
    @index.index_single("/fake.rb", <<~RUBY)
      class Foo; end
      module Bar; end

      CONSTANT = 1
    RUBY

    result = RubyLsp::Requests::WorkspaceSymbol.new("Foo", @index).run.first
    assert_equal("Foo", T.must(result).name)
    assert_equal(RubyLsp::Constant::SymbolKind::CLASS, T.must(result).kind)

    result = RubyLsp::Requests::WorkspaceSymbol.new("Bar", @index).run.first
    assert_equal("Bar", T.must(result).name)
    assert_equal(RubyLsp::Constant::SymbolKind::NAMESPACE, T.must(result).kind)

    result = RubyLsp::Requests::WorkspaceSymbol.new("CONST", @index).run.first
    assert_equal("CONSTANT", T.must(result).name)
    assert_equal(RubyLsp::Constant::SymbolKind::CONSTANT, T.must(result).kind)
  end

  def test_fuzzy_matches_symbols
    @index.index_single("/fake.rb", <<~RUBY)
      class Foo; end
      module Bar; end

      CONSTANT = 1
    RUBY

    result = RubyLsp::Requests::WorkspaceSymbol.new("Floo", @index).run.first
    assert_equal("Foo", T.must(result).name)
    assert_equal(RubyLsp::Constant::SymbolKind::CLASS, T.must(result).kind)

    result = RubyLsp::Requests::WorkspaceSymbol.new("Bear", @index).run.first
    assert_equal("Bar", T.must(result).name)
    assert_equal(RubyLsp::Constant::SymbolKind::NAMESPACE, T.must(result).kind)

    result = RubyLsp::Requests::WorkspaceSymbol.new("CONF", @index).run.first
    assert_equal("CONSTANT", T.must(result).name)
    assert_equal(RubyLsp::Constant::SymbolKind::CONSTANT, T.must(result).kind)
  end

  def test_matches_only_gem_symbols_if_typechecker_is_present
    RubyLsp::DependencyDetector.const_set(:HAS_TYPECHECKER, true)

    @index.index_single("#{RubyLsp::WORKSPACE_URI.to_standardized_path}/workspace_symbol_foo.rb", <<~RUBY)
      class Foo; end
    RUBY

    path = "#{Bundler.bundle_path}/gems/fake-gem-0.1.0/lib/gem_symbol_foo.rb"
    @index.index_single(path, <<~RUBY)
      class Foo; end
    RUBY

    result = RubyLsp::Requests::WorkspaceSymbol.new("Foo", @index).run
    assert_equal(1, result.length)
    assert_equal(URI::Generic.from_path(path: path).to_s, T.must(result.first).location.uri)
  end

  def test_symbols_include_container_name
    @index.index_single("/fake.rb", <<~RUBY)
      module Foo
        class Bar; end
      end
    RUBY

    result = RubyLsp::Requests::WorkspaceSymbol.new("Foo::Bar", @index).run.first
    assert_equal("Foo::Bar", T.must(result).name)
    assert_equal(RubyLsp::Constant::SymbolKind::CLASS, T.must(result).kind)
    assert_equal("Foo", T.must(result).container_name)
  end
end
