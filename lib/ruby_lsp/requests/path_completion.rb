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
        @position = position
      end

      sig { override.returns(T.all(T::Array[Interface::CompletionItem], Object)) }
      def run
        # We can't verify if we're inside a require when there are syntax errors
        return [] if @document.syntax_error?

        target = T.let(find, T.nilable(SyntaxTree::TStringContent))
        # no target means the we are not inside a `require` call
        return [] unless target

        text = target.value
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

      sig { returns(T.nilable(SyntaxTree::TStringContent)) }
      def find
        char_position = @document.create_scanner.find_char_position(@position)
        matched, parent = @document.locate(
          T.must(@document.tree),
          char_position,
          node_types: [SyntaxTree::Command, SyntaxTree::CommandCall, SyntaxTree::CallNode],
        )

        return unless matched && parent

        case matched
        when SyntaxTree::Command, SyntaxTree::CallNode, SyntaxTree::CommandCall
          message = matched.message
          return if message.is_a?(Symbol)
          return unless message.value == "require"

          args = matched.arguments
          args = args.arguments if args.is_a?(SyntaxTree::ArgParen)
          return if args.nil? || args.is_a?(SyntaxTree::ArgsForward)

          argument = args.parts.first
          return unless argument.is_a?(SyntaxTree::StringLiteral)

          path_node = argument.parts.first
          return unless path_node.is_a?(SyntaxTree::TStringContent)
          return unless (path_node.location.start_char..path_node.location.end_char).cover?(char_position)

          path_node
        end
      end

      sig { params(label: String, insert_text: String).returns(Interface::CompletionItem) }
      def build_completion(label, insert_text)
        Interface::CompletionItem.new(
          label: label,
          text_edit: Interface::TextEdit.new(
            range: Interface::Range.new(
              start: @position,
              end: @position,
            ),
            new_text: insert_text,
          ),
          kind: Constant::CompletionItemKind::REFERENCE,
        )
      end
    end
  end
end
