# typed: strict
# frozen_string_literal: true

module RubyLsp
  module Requests
    class CompletionResolve < Request
      extend T::Sig
      include Requests::Support::Common

      MAX_DOCUMENTATION_ENTRIES = 10

      sig { params(index: RubyIndexer::Index, item: T::Hash[Symbol, T.untyped]).void }
      def initialize(index, item)
        super()
        @index = index
        @item = item
      end

      sig { override.returns(Interface::CompletionItem) }
      def perform
        label = @item[:label]
        entries = @index[label] || []
        Interface::CompletionItem.new(
          label: label,
          label_details: Interface::CompletionItemLabelDetails.new(
            description: entries.take(MAX_DOCUMENTATION_ENTRIES).map(&:file_name).join(","),
          ),
          documentation: Interface::MarkupContent.new(
            kind: "markdown",
            value: markdown_from_index_entries(label, entries, MAX_DOCUMENTATION_ENTRIES),
          ),
        )
      end
    end
  end
end
