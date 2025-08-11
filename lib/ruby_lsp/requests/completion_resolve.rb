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
      include Requests::Support::Common

      # set a limit on the number of documentation entries returned, to avoid rendering performance issues
      # https://github.com/Shopify/ruby-lsp/pull/1798
      MAX_DOCUMENTATION_ENTRIES = 10

      #: (GlobalState global_state, Hash[Symbol, untyped] item) -> void
      def initialize(global_state, item)
        super()
        @index = global_state.index #: RubyIndexer::Index
        @item = item
      end

      # @override
      #: -> Hash[Symbol, untyped]
      def perform
        return @item if @item.dig(:data, :skip_resolve)

        # Based on the spec https://microsoft.github.io/language-server-protocol/specification#textDocument_completion,
        # a completion resolve request must always return the original completion item without modifying ANY fields
        # other than detail and documentation (NOT labelDetails). If we modify anything, the completion behavior might
        # be broken.
        #
        # For example, forgetting to return the `insertText` included in the original item will make the editor use the
        # `label` for the text edit instead
        label = @item[:label].dup
        return keyword_resolve(@item) if @item.dig(:data, :keyword)

        entries = @index[label] || []

        owner_name = @item.dig(:data, :owner_name)

        if owner_name
          entries = entries.select do |entry|
            (entry.is_a?(RubyIndexer::Entry::Member) || entry.is_a?(RubyIndexer::Entry::InstanceVariable) ||
            entry.is_a?(RubyIndexer::Entry::MethodAlias) || entry.is_a?(RubyIndexer::Entry::ClassVariable)) &&
              entry.owner&.name == owner_name
          end
        end

        first_entry = entries.first #: as !nil

        if first_entry.is_a?(RubyIndexer::Entry::Member)
          label = +"#{label}#{first_entry.decorated_parameters}"
          label << first_entry.formatted_signatures
        end

        guessed_type = @item.dig(:data, :guessed_type)

        extra_links = if guessed_type
          label << "\n\nGuessed receiver: #{guessed_type}"
          "[Learn more about guessed types](#{GUESSED_TYPES_URL})"
        end

        @item[:documentation] = Interface::MarkupContent.new(
          kind: "markdown",
          value: markdown_from_index_entries(label, entries, MAX_DOCUMENTATION_ENTRIES, extra_links: extra_links),
        )

        @item
      end

      private

      #: (Hash[Symbol, untyped] item) -> Hash[Symbol, untyped]
      def keyword_resolve(item)
        keyword = item[:label]
        content = KEYWORD_DOCS[keyword]

        if content
          doc_path = File.join(STATIC_DOCS_PATH, "#{keyword}.md")

          @item[:documentation] = Interface::MarkupContent.new(
            kind: "markdown",
            value: <<~MARKDOWN.chomp,
              ```ruby
              #{keyword}
              ```

              [Read more](#{doc_path})

              #{content}
            MARKDOWN
          )
        end

        item
      end
    end
  end
end
