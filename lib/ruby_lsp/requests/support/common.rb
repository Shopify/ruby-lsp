# typed: strict
# frozen_string_literal: true

module RubyLsp
  module Requests
    module Support
      module Common
        extend T::Sig

        sig { params(node: SyntaxTree::Node).returns(Interface::Range) }
        def range_from_syntax_tree_node(node)
          loc = node.location

          Interface::Range.new(
            start: Interface::Position.new(
              line: loc.start_line - 1,
              character: loc.start_column,
            ),
            end: Interface::Position.new(line: loc.end_line - 1, character: loc.end_column),
          )
        end

        sig do
          params(node: T.any(SyntaxTree::ConstPathRef, SyntaxTree::ConstRef, SyntaxTree::TopConstRef)).returns(String)
        end
        def full_constant_name(node)
          name = +node.constant.value
          constant = T.let(node, SyntaxTree::Node)

          while constant.is_a?(SyntaxTree::ConstPathRef)
            constant = constant.parent

            case constant
            when SyntaxTree::ConstPathRef
              name.prepend("#{constant.constant.value}::")
            when SyntaxTree::VarRef
              name.prepend("#{constant.value.value}::")
            end
          end

          name
        end

        sig { params(node: T.nilable(SyntaxTree::Node), range: T.nilable(T::Range[Integer])).returns(T::Boolean) }
        def visible?(node, range)
          return true if range.nil?
          return false if node.nil?

          loc = node.location
          range.cover?(loc.start_line - 1) && range.cover?(loc.end_line - 1)
        end

        sig do
          params(
            node: SyntaxTree::Node,
            path: String,
            name: String,
            test_command: String,
            type: String,
          ).returns(Interface::CodeLens)
        end
        def create_code_lens(node, path:, name:, test_command:, type:)
          title = type == "test" ? "Run" : "Debug"
          command = type == "test" ? "rubyLsp.runTest" : "rubyLsp.debugTest"
          range = range_from_syntax_tree_node(node)
          arguments = [
            path,
            name,
            test_command,
            {
              start_line: node.location.start_line - 1,
              start_column: node.location.start_column,
              end_line: node.location.end_line - 1,
              end_column: node.location.end_column,
            },
          ]

          Interface::CodeLens.new(
            range: range,
            command: Interface::Command.new(
              title: title,
              command: command,
              arguments: arguments,
            ),
            data: { type: type },
          )
        end
      end
    end
  end
end
