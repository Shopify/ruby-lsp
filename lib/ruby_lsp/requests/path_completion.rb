# typed: strict
# frozen_string_literal: true

module RubyLsp
  module Requests
    # ![Path completion demo](../../path_completion.gif)
    #
    # The [completion](https://microsoft.github.io/language-server-protocol/specification#textDocument_completion)
    # request looks up Ruby files in the $LOAD_PATH to suggest path completion inside `require` statements.
    #
    # # Example
    #
    # ```ruby
    # require "ruby_lsp/requests" # --> completion: suggests `base_request`, `code_actions`, ...
    # ```
    class PathCompletion < Listener
      extend T::Sig
      extend T::Generic

      ResponseType = type_member { { fixed: T::Array[Interface::CompletionItem] } }

      sig { override.returns(ResponseType) }
      attr_reader :response

      sig { params(index: RubyIndexer::Index, emitter: EventEmitter, message_queue: Thread::Queue).void }
      def initialize(index, emitter, message_queue)
        super(emitter, message_queue)
        @response = T.let([], ResponseType)
        @index = index

        emitter.register(self, :on_tstring_content)
      end

      sig { params(node: SyntaxTree::TStringContent).void }
      def on_tstring_content(node)
        @index.search_require_paths(node.value).sort!.each do |path|
          @response << build_completion(path, node)
        end
      end

      private

      sig { params(label: String, node: SyntaxTree::TStringContent).returns(Interface::CompletionItem) }
      def build_completion(label, node)
        Interface::CompletionItem.new(
          label: label,
          text_edit: Interface::TextEdit.new(
            range: range_from_syntax_tree_node(node),
            new_text: label,
          ),
          kind: Constant::CompletionItemKind::REFERENCE,
        )
      end
    end
  end
end
