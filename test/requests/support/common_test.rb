# typed: true
# frozen_string_literal: true

require "test_helper"

module RubyLsp
  class CommonTest < Minitest::Test
    include Requests::Support::Common

    def test_kinds_are_defined_for_every_entry
      index = RubyIndexer::Index.new
      index.index_all

      entries = index.instance_variable_get(:@entries).values.flatten
      entries.each do |entry|
        kind = kind_for_entry(entry)
        refute_equal(kind, Constant::SymbolKind::NULL, "Kind not defined for entry: #{entry.inspect}")
      end
    end
  end
end
