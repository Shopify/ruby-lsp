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

      CONSTANT_KINDS = T.let(
        [
          Constant::CompletionItemKind::CLASS,
          Constant::CompletionItemKind::MODULE,
          Constant::CompletionItemKind::CONSTANT,
        ].freeze,
        T::Array[Integer],
      )

      # set a limit on the number of documentation entries returned, to avoid rendering performance issues
      # https://github.com/Shopify/ruby-lsp/pull/1798
      MAX_DOCUMENTATION_ENTRIES = 10

      sig { params(global_state: GlobalState, item: T::Hash[Symbol, T.untyped]).void }
      def initialize(global_state, item)
        super()
        @index = T.let(global_state.index, RubyIndexer::Index)
        @item = item
      end

      sig { override.returns(T.nilable(Interface::CompletionItem)) }
      def perform
        label = @item[:label]
        owner = @item.dig(:data, :owner)

        if CONSTANT_KINDS.include?(@item[:kind])
          constant_item_documentation(label, T.must(@index.get_constant(label)))
        elsif owner
          known_method_item_documentation(label, T.must(@index.resolve_method(label, owner)))
        end
      end

      private

      sig { params(label: String, entry: RubyIndexer::Entry::Member).returns(Interface::CompletionItem) }
      def known_method_item_documentation(label, entry)
        declarations = T.cast(
          entry.declarations.take(MAX_DOCUMENTATION_ENTRIES),
          T::Array[RubyIndexer::Entry::MemberDeclaration],
        )

        Interface::CompletionItem.new(
          label: label,
          label_details: Interface::CompletionItemLabelDetails.new(
            detail: "(#{T.must(declarations.first).parameters.map(&:decorated_name).join(", ")})",
            description: declarations.map(&:file_name).join(","),
          ),
          documentation: Interface::MarkupContent.new(
            kind: "markdown",
            value: markdown_from_index_entries(label, entry, MAX_DOCUMENTATION_ENTRIES),
          ),
        )
      end

      sig { params(label: String, entry: RubyIndexer::Entry).returns(Interface::CompletionItem) }
      def constant_item_documentation(label, entry)
        file_names = entry.declarations.take(MAX_DOCUMENTATION_ENTRIES).map(&:file_name)

        Interface::CompletionItem.new(
          label: label,
          label_details: Interface::CompletionItemLabelDetails.new(description: file_names.join(",")),
          documentation: Interface::MarkupContent.new(
            kind: "markdown",
            value: markdown_from_index_entries(label, entry, MAX_DOCUMENTATION_ENTRIES),
          ),
        )
      end
    end
  end
end
