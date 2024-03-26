# typed: strict
# frozen_string_literal: true

module RubyLsp
  module Requests
    # The [completionItem/resolve](https://microsoft.github.io/language-server-protocol/specification#completionItem_resolve)
    # request provides additional information about the currently selected completion. Specifically, the `labelDetails`
    # and `documentation` fields are provided, which are omitted from the completion items returned by
    # `textDocument/completion`.
    #
    # The `labelDetails` field lists the files where the completion item is defined, and the `documentation` field
    # includes any available documentation for those definitions.
    #
    # At most 10 definitions are included, to ensure low latency during request processing and rendering the completion
    # item.
    class CompletionResolve < Request
      extend T::Sig
      include Requests::Support::Common

      # set a limit on the number of documentation entries returned, to avoid rendering performance issues
      # https://github.com/Shopify/ruby-lsp/pull/1798
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
