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

      sig { params(emitter: EventEmitter, message_queue: Thread::Queue).void }
      def initialize(emitter, message_queue)
        super
        @response = T.let([], ResponseType)

        emitter.register(self, :on_tstring_content)
      end

      sig { params(node: SyntaxTree::TStringContent).void }
      def on_tstring_content(node)
        paths = $LOAD_PATH.flat_map do |p|
          Dir.glob("#{node.value}**/*.rb", base: p).map! do |path|
            path.delete_suffix(".rb")
          end
        end
        paths.sort!
        paths.each { |path| @response << build_completion(path, node) }
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
