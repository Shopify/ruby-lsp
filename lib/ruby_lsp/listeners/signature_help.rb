# typed: strict
# frozen_string_literal: true

module RubyLsp
  module Listeners
    class SignatureHelp
      extend T::Sig
      include Requests::Support::Common

      sig do
        params(
          response_builder: ResponseBuilders::SignatureHelp,
          global_state: GlobalState,
          node_context: NodeContext,
          dispatcher: Prism::Dispatcher,
          sorbet_level: RubyDocument::SorbetLevel,
        ).void
      end
      def initialize(response_builder, global_state, node_context, dispatcher, sorbet_level)
        @sorbet_level = sorbet_level
        @response_builder = response_builder
        @global_state = global_state
        @index = T.let(global_state.index, RubyIndexer::Index)
        @type_inferrer = T.let(global_state.type_inferrer, TypeInferrer)
        @node_context = node_context
        dispatcher.register(self, :on_call_node_enter)
      end

      sig { params(node: Prism::CallNode).void }
      def on_call_node_enter(node)
        return if sorbet_level_true_or_higher?(@sorbet_level)

        message = node.message
        return unless message

        type = @type_inferrer.infer_receiver_type(@node_context)
        return unless type

        methods = @index.resolve_method(message, type.name)
        return unless methods

        target_method = methods.first
        return unless target_method

        signatures = target_method.signatures

        # If the method doesn't have any parameters, there's no need to show signature help
        return if signatures.empty?

        name = target_method.name
        title = +""

        extra_links = if type.is_a?(TypeInferrer::GuessedType)
          title << "\n\nGuessed receiver: #{type.name}"
          "[Learn more about guessed types](#{GUESSED_TYPES_URL})"
        end

        active_signature, active_parameter = determine_active_signature_and_parameter(node, signatures)

        signature_help = Interface::SignatureHelp.new(
          signatures: generate_signatures(signatures, name, methods, title, extra_links),
          active_signature: active_signature,
          active_parameter: active_parameter,
        )
        @response_builder.replace(signature_help)
      end

      private

      sig do
        params(node: Prism::CallNode, signatures: T::Array[RubyIndexer::Entry::Signature]).returns([Integer, Integer])
      end
      def determine_active_signature_and_parameter(node, signatures)
        arguments_node = node.arguments
        arguments = arguments_node&.arguments || []

        # Find the first signature that matches the current arguments. If the user is invoking a method incorrectly and
        # none of the signatures match, we show the first one
        active_sig_index = signatures.find_index do |signature|
          signature.matches?(arguments)
        end || 0

        parameter_length = [T.must(signatures[active_sig_index]).parameters.length - 1, 0].max
        active_parameter = (arguments.length - 1).clamp(0, parameter_length)

        # If there are arguments, then we need to check if there's a trailing comma after the end of the last argument
        # to advance the active parameter to the next one
        if arguments_node &&
            node.slice.byteslice(arguments_node.location.end_offset - node.location.start_offset) == ","
          active_parameter += 1
        end

        [active_sig_index, active_parameter]
      end

      sig do
        params(
          signatures: T::Array[RubyIndexer::Entry::Signature],
          method_name: String,
          methods: T::Array[RubyIndexer::Entry],
          title: String,
          extra_links: T.nilable(String),
        ).returns(T::Array[Interface::SignatureInformation])
      end
      def generate_signatures(signatures, method_name, methods, title, extra_links)
        signatures.map do |signature|
          Interface::SignatureInformation.new(
            label:  "#{method_name}(#{signature.format})",
            parameters: signature.parameters.map { |param| Interface::ParameterInformation.new(label: param.name) },
            documentation: Interface::MarkupContent.new(
              kind: "markdown",
              value: markdown_from_index_entries(title, methods, extra_links: extra_links),
            ),
          )
        end
      end
    end
  end
end
