# typed: strict
# frozen_string_literal: true

module RubyLsp
  module Requests
    # ![Selection ranges demo](../../misc/selection_ranges.gif)
    #
    # The [selection ranges](https://microsoft.github.io/language-server-protocol/specification#textDocument_selectionRange)
    # request informs the editor of ranges that the user may want to select based on the location(s)
    # of their cursor(s).
    #
    # Trigger this request with: Ctrl + Shift + -> or Ctrl + Shift + <-
    #
    # # Example
    #
    # ```ruby
    # def foo # --> The next selection range encompasses the entire method definition.
    #   puts "Hello, world!" # --> Cursor is on this line
    # end
    # ```
    class SelectionRanges < BaseRequest
      extend T::Sig

      NODES_THAT_CAN_BE_PARENTS = T.let([
        SyntaxTree::Assign,
        SyntaxTree::ArrayLiteral,
        SyntaxTree::Begin,
        SyntaxTree::BraceBlock,
        SyntaxTree::Call,
        SyntaxTree::Case,
        SyntaxTree::ClassDeclaration,
        SyntaxTree::Command,
        SyntaxTree::Def,
        SyntaxTree::Defs,
        SyntaxTree::DoBlock,
        SyntaxTree::Elsif,
        SyntaxTree::Else,
        SyntaxTree::EmbDoc,
        SyntaxTree::Ensure,
        SyntaxTree::FCall,
        SyntaxTree::For,
        SyntaxTree::HashLiteral,
        SyntaxTree::Heredoc,
        SyntaxTree::HeredocBeg,
        SyntaxTree::HshPtn,
        SyntaxTree::If,
        SyntaxTree::In,
        SyntaxTree::Lambda,
        SyntaxTree::MethodAddBlock,
        SyntaxTree::ModuleDeclaration,
        SyntaxTree::Params,
        SyntaxTree::Rescue,
        SyntaxTree::RescueEx,
        SyntaxTree::StringConcat,
        SyntaxTree::StringLiteral,
        SyntaxTree::Unless,
        SyntaxTree::Until,
        SyntaxTree::VCall,
        SyntaxTree::When,
        SyntaxTree::While,
      ].freeze, T::Array[T.class_of(SyntaxTree::Node)])

      sig { params(document: Document).void }
      def initialize(document)
        super(document)

        @ranges = T.let([], T::Array[Support::SelectionRange])
        @stack = T.let([], T::Array[Support::SelectionRange])
      end

      sig { override.returns(T.all(T::Array[Support::SelectionRange], Object)) }
      def run
        visit(@document.tree) if @document.parsed?
        @ranges.reverse!
      end

      private

      sig { override.params(node: T.nilable(SyntaxTree::Node)).void }
      def visit(node)
        return if node.nil?

        range = create_selection_range(node.location, @stack.last)

        @ranges << range
        return if node.child_nodes.empty?

        @stack << range if NODES_THAT_CAN_BE_PARENTS.include?(node.class)
        visit_all(node.child_nodes)
        @stack.pop if NODES_THAT_CAN_BE_PARENTS.include?(node.class)
      end

      sig do
        params(
          location: SyntaxTree::Location,
          parent: T.nilable(Support::SelectionRange),
        ).returns(Support::SelectionRange)
      end
      def create_selection_range(location, parent = nil)
        RubyLsp::Requests::Support::SelectionRange.new(
          range: LanguageServer::Protocol::Interface::Range.new(
            start: LanguageServer::Protocol::Interface::Position.new(
              line: location.start_line - 1,
              character: location.start_column,
            ),
            end: LanguageServer::Protocol::Interface::Position.new(
              line: location.end_line - 1,
              character: location.end_column,
            ),
          ),
          parent: parent,
        )
      end
    end
  end
end
