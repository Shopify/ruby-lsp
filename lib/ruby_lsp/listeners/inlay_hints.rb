# typed: strict
# frozen_string_literal: true

module RubyLsp
  module Listeners
    class InlayHints
      include Requests::Support::Common

      RESCUE_STRING_LENGTH = "rescue".length #: Integer

      #: (ResponseBuilders::CollectionResponseBuilder[Interface::InlayHint] response_builder, RequestConfig hints_configuration, Prism::Dispatcher dispatcher) -> void
      def initialize(response_builder, hints_configuration, dispatcher)
        @response_builder = response_builder
        @hints_configuration = hints_configuration

        dispatcher.register(self, :on_rescue_node_enter, :on_implicit_node_enter)
      end

      #: (Prism::RescueNode node) -> void
      def on_rescue_node_enter(node)
        return unless @hints_configuration.enabled?(:implicitRescue)
        return unless node.exceptions.empty?

        loc = node.location

        @response_builder << Interface::InlayHint.new(
          position: { line: loc.start_line - 1, character: loc.start_column + RESCUE_STRING_LENGTH },
          label: "StandardError",
          padding_left: true,
          tooltip: "StandardError is implied in a bare rescue",
        )
      end

      #: (Prism::ImplicitNode node) -> void
      def on_implicit_node_enter(node)
        return unless @hints_configuration.enabled?(:implicitHashValue)

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
