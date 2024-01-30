# typed: strict
# frozen_string_literal: true

module RubyLsp
  module Listeners
    class InlayHints
      extend T::Sig
      include Requests::Support::Common

      RESCUE_STRING_LENGTH = T.let("rescue".length, Integer)

      sig do
        params(
          response_builder: ResponseBuilders::CollectionResponseBuilder[Interface::InlayHint],
          range: T::Range[Integer],
          hints_configuration: RequestConfig,
          dispatcher: Prism::Dispatcher,
        ).void
      end
      def initialize(response_builder, range, hints_configuration, dispatcher)
        @response_builder = response_builder
        @range = range
        @hints_configuration = hints_configuration

        dispatcher.register(self, :on_rescue_node_enter, :on_implicit_node_enter)
      end

      sig { params(node: Prism::RescueNode).void }
      def on_rescue_node_enter(node)
        return unless @hints_configuration.enabled?(:implicitRescue)
        return unless node.exceptions.empty?

        loc = node.location
        return unless visible?(node, @range)

        @response_builder << Interface::InlayHint.new(
          position: { line: loc.start_line - 1, character: loc.start_column + RESCUE_STRING_LENGTH },
          label: "StandardError",
          padding_left: true,
          tooltip: "StandardError is implied in a bare rescue",
        )
      end

      sig { params(node: Prism::ImplicitNode).void }
      def on_implicit_node_enter(node)
        return unless @hints_configuration.enabled?(:implicitHashValue)
        return unless visible?(node, @range)

        node_value = node.value
        loc = node.location
        tooltip = ""
        node_name = ""
        case node_value
        when Prism::CallNode
          node_name = node_value.name
          tooltip = "This is a method call. Method name: #{node_name}"
        when Prism::ConstantReadNode
          node_name = node_value.name
          tooltip = "This is a constant: #{node_name}"
        when Prism::LocalVariableReadNode
          node_name = node_value.name
          tooltip = "This is a local variable: #{node_name}"
        end

        @response_builder << Interface::InlayHint.new(
          position: { line: loc.start_line - 1, character: loc.start_column + node_name.length + 1 },
          label: node_name,
          padding_left: true,
          tooltip: tooltip,
        )
      end
    end
  end
end
