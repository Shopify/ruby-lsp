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

      METHOD_KINDS = [
        Constant::CompletionItemKind::METHOD,
        Constant::CompletionItemKind::CONSTRUCTOR,
        Constant::CompletionItemKind::FUNCTION,
      ].freeze #: Array[Integer]

      # set a limit on the number of documentation entries returned, to avoid rendering performance issues
      # https://github.com/Shopify/ruby-lsp/pull/1798
      MAX_DOCUMENTATION_ENTRIES = 10

      #: (GlobalState global_state, Hash[Symbol, untyped] item) -> void
      def initialize(global_state, item)
        super()
        @graph = global_state.graph #: Rubydex::Graph
        @item = item
      end

      # @override
      #: -> Hash[Symbol, untyped]
      def perform
        return @item if @item.dig(:data, :skip_resolve)
        return keyword_resolve if @item.dig(:data, :keyword)
        return @item if @item[:kind] == Constant::CompletionItemKind::FILE

        # Based on the spec https://microsoft.github.io/language-server-protocol/specification#textDocument_completion,
        # a completion resolve request must always return the original completion item without modifying ANY fields
        # other than detail and documentation (NOT labelDetails). If we modify anything, the completion behavior might
        # be broken.
        #
        # For example, forgetting to return the `insertText` included in the original item will make the editor use the
        # `label` for the text edit instead
        declaration = resolve_declaration
        return @item unless declaration

        guessed_type = @item.dig(:data, :guessed_type)
        title = @item[:label].dup

        # TODO: when Rubydex exposes method signatures via `Rubydex::MethodDefinition#signatures`, append the formatted
        # parameter list and overload count to the title here (see the legacy `decorated_parameters` /
        # `formatted_signatures` rendering on `RubyIndexer::Entry::Member`).

        extra_links = if guessed_type
          title << "\n\nGuessed receiver: #{guessed_type}"
          "[Learn more about guessed types](#{GUESSED_TYPES_URL})"
        end

        @item[:documentation] = Interface::MarkupContent.new(
          kind: "markdown",
          value: markdown_from_definitions(
            title,
            declaration.definitions,
            MAX_DOCUMENTATION_ENTRIES,
            extra_links: extra_links,
          ),
        )

        @item
      end

      private

      # Find the Rubydex declaration that matches the completion item. Constants are looked up by their fully qualified
      # name (set when the completion was produced); members (methods, instance/class variables) are resolved by walking
      # the owner namespace and its ancestors so that inherited and aliased members are surfaced correctly.
      #: -> Rubydex::Declaration?
      def resolve_declaration
        data = @item[:data] || {}

        if (fully_qualified_name = data[:fully_qualified_name])
          @graph[fully_qualified_name]
        elsif (owner_name = data[:owner_name])
          owner = @graph[owner_name]
          return unless owner.is_a?(Rubydex::Namespace)

          member_name = if METHOD_KINDS.include?(@item[:kind])
            "#{@item[:label]}()"
          else
            @item[:label]
          end

          owner.find_member(member_name)
        end
      end

      #: -> Hash[Symbol, untyped]
      def keyword_resolve
        keyword = @graph.keyword(@item[:label])

        if keyword
          @item[:documentation] = Interface::MarkupContent.new(
            kind: "markdown",
            value: <<~MARKDOWN.chomp,
              ```ruby
              #{keyword.name}
              ```

              #{keyword.documentation}
            MARKDOWN
          )
        end

        @item
      end
    end
  end
end
