# typed: strict
# frozen_string_literal: true

module RubyLsp
  module Requests
    # ![Completion resolve demo](../../completion_resolve.gif)
    #
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
    #
    # # Example
    #
    # ```ruby
    # A # -> as the user cycles through completion items, the documentation will be resolved and displayed
    # ```
    class CompletionResolve < Request
      extend T::Sig
      include Requests::Support::Common

      # set a limit on the number of documentation entries returned, to avoid rendering performance issues
      # https://github.com/Shopify/ruby-lsp/pull/1798
      MAX_DOCUMENTATION_ENTRIES = 10

      sig { params(global_state: GlobalState, item: T::Hash[Symbol, T.untyped]).void }
      def initialize(global_state, item)
        super()
        @index = T.let(global_state.index, RubyIndexer::Index)
        @item = item
      end

      sig { override.returns(T::Hash[Symbol, T.untyped]) }
      def perform
        # Based on the spec https://microsoft.github.io/language-server-protocol/specification#textDocument_completion,
        # a completion resolve request must always return the original completion item without modifying ANY fields
        # other than label details and documentation. If we modify anything, the completion behaviour might be broken.
        #
        # For example, forgetting to return the `insertText` included in the original item will make the editor use the
        # `label` for the text edit instead
        label = @item[:label]
        entries = @index[label] || []

        owner_name = @item.dig(:data, :owner_name)

        if owner_name
          entries = entries.select do |entry|
            (entry.is_a?(RubyIndexer::Entry::Member) || entry.is_a?(RubyIndexer::Entry::InstanceVariable)) &&
              entry.owner&.name == owner_name
          end
        end

        @item[:labelDetails] = Interface::CompletionItemLabelDetails.new(
          description: entries.take(MAX_DOCUMENTATION_ENTRIES).map(&:file_name).join(","),
        )

        @item[:documentation] = Interface::MarkupContent.new(
          kind: "markdown",
          value: markdown_from_index_entries(label, entries, MAX_DOCUMENTATION_ENTRIES),
        )

        @item
      end
    end
  end
end
