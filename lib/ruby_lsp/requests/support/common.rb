# typed: strict
# frozen_string_literal: true

module RubyLsp
  module Requests
    module Support
      module Common
        # WARNING: Methods in this class may be used by Ruby LSP extensions such as https://github.com/Shopify/ruby-lsp-rails,
        # or extensions by created by developers outside of Shopify, so be cautious of changing anything.
        extend T::Sig

        sig { params(node: YARP::Node).returns(Interface::Range) }
        def range_from_node(node)
          loc = node.location

          Interface::Range.new(
            start: Interface::Position.new(
              line: loc.start_line - 1,
              character: loc.start_column,
            ),
            end: Interface::Position.new(line: loc.end_line - 1, character: loc.end_column),
          )
        end

        sig { params(location: YARP::Location).returns(Interface::Range) }
        def range_from_location(location)
          Interface::Range.new(
            start: Interface::Position.new(
              line: location.start_line - 1,
              character: location.start_column,
            ),
            end: Interface::Position.new(line: location.end_line - 1, character: location.end_column),
          )
        end

        sig { params(node: T.nilable(YARP::Node), range: T.nilable(T::Range[Integer])).returns(T::Boolean) }
        def visible?(node, range)
          return true if range.nil?
          return false if node.nil?

          loc = node.location
          range.cover?(loc.start_line - 1) && range.cover?(loc.end_line - 1)
        end

        sig do
          params(
            node: YARP::Node,
            title: String,
            command_name: String,
            arguments: T.nilable(T::Array[T.untyped]),
            data: T.nilable(T::Hash[T.untyped, T.untyped]),
          ).returns(Interface::CodeLens)
        end
        def create_code_lens(node, title:, command_name:, arguments:, data:)
          range = range_from_node(node)

          Interface::CodeLens.new(
            range: range,
            command: Interface::Command.new(
              title: title,
              command: command_name,
              arguments: arguments,
            ),
            data: data,
          )
        end
      end
    end
  end
end
