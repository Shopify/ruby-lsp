# typed: strict
# frozen_string_literal: true

module RubyLsp
  module Requests
    # ![Path completion demo](../../misc/path_completion.gif)
    #
    # The [completion](https://microsoft.github.io/language-server-protocol/specification#textDocument_completion)
    # request looks up Ruby files in the $LOAD_PATH to suggest path completion inside `require` statements.
    #
    # # Example
    #
    # ```ruby
    # require "ruby_lsp/requests" # --> completion: suggests `base_request`, `code_actions`, ...
    # ```
    class PathCompletion < BaseRequest
      extend T::Sig

      sig { params(document: Document, position: Document::PositionShape).void }
      def initialize(document, position)
        super(document)

        @tree = T.let(Support::PrefixTree.new(collect_load_path_files), Support::PrefixTree)

        char_position = document.create_scanner.find_char_position(position)
        @target = T.let(find(char_position), T.nilable(SyntaxTree::TStringContent))
      end

      sig { override.returns(T.all(T::Array[LanguageServer::Protocol::Interface::CompletionItem], Object)) }
      def run
        # no @target means the we are not inside a `require` call
        return [] unless @target

        text = @target.value
        @tree.search(text).sort.map! do |path|
          build_completion(path, path.delete_prefix(text))
        end
      end

      private

      sig { returns(T::Array[String]) }
      def collect_load_path_files
        $LOAD_PATH.flat_map do |p|
          Dir.glob("**/*.rb", base: p)
        end.map! do |result|
          result.delete_suffix!(".rb")
        end
      end

      sig { params(position: Integer).returns(T.nilable(SyntaxTree::TStringContent)) }
      def find(position)
        matched, parent = locate(
          T.must(@document.tree),
          position,
          node_types: [SyntaxTree::Command, SyntaxTree::CommandCall, SyntaxTree::CallNode],
        )

        return unless matched && parent

        case matched
        when SyntaxTree::Command, SyntaxTree::CallNode, SyntaxTree::CommandCall
          return unless matched.message.value == "require"

          args = matched.arguments
          args = args.arguments if args.is_a?(SyntaxTree::ArgParen)

          path_node = args.parts.first.parts.first
          return unless path_node
          return unless (path_node.location.start_char..path_node.location.end_char).cover?(position)

          path_node
        end
      end

      sig do
        params(label: String, insert_text: String).returns(LanguageServer::Protocol::Interface::CompletionItem)
      end
      def build_completion(label, insert_text)
        LanguageServer::Protocol::Interface::CompletionItem.new(
          label: label,
          insert_text: insert_text,
          kind: LanguageServer::Protocol::Constant::CompletionItemKind::REFERENCE,
        )
      end
    end
  end
end
