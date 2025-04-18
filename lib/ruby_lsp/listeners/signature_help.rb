# typed: strict
# frozen_string_literal: true

module RubyLsp
  module Listeners
    class SignatureHelp
      include Requests::Support::Common

      #: (ResponseBuilders::SignatureHelp response_builder, GlobalState global_state, NodeContext node_context, Prism::Dispatcher dispatcher, RubyDocument::SorbetLevel sorbet_level, Integer char_position) -> void
      def initialize(response_builder, global_state, node_context, dispatcher, sorbet_level, char_position) # rubocop:disable Metrics/ParameterLists
        @sorbet_level = sorbet_level
        @response_builder = response_builder
        @global_state = global_state
        @index = global_state.index #: RubyIndexer::Index
        @type_inferrer = global_state.type_inferrer #: TypeInferrer
        @node_context = node_context
        @char_position = char_position
        dispatcher.register(self, :on_call_node_enter)
      end

      #: (Prism::CallNode node) -> void
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

      #: (Prism::CallNode node, Array[RubyIndexer::Entry::Signature] signatures) -> [Integer, Integer]
      def determine_active_signature_and_parameter(node, signatures)
        arguments_node = node.arguments
        arguments = arguments_node&.arguments || []

        # Find the first signature that matches the current arguments. If the user is invoking a method incorrectly and
        # none of the signatures match, we show the first one
        active_sig_index = signatures.find_index do |signature|
          signature.matches?(arguments)
        end || 0

        signature = signatures[active_sig_index]
        parameter_length = signature&.parameters&.length || 0
        flat_arguments = arguments.flat_map { _1.is_a?(Prism::KeywordHashNode) ? _1.elements : _1 }

        # If complex syntax is involved, we just give up showing active parameter instead of showing incorrect one
        if flat_arguments.any? do |argument|
          argument.is_a?(Prism::SplatNode) ||
              argument.is_a?(Prism::AssocSplatNode) ||
              argument.is_a?(Prism::ForwardingArgumentsNode)
        end
          return [active_sig_index, parameter_length]
        end
        if signature&.parameters&.any? do |param|
          param.is_a?(RubyIndexer::Entry::RestParameter) ||
              param.is_a?(RubyIndexer::Entry::KeywordRestParameter) ||
              param.is_a?(RubyIndexer::Entry::ForwardingParameter)
        end
          return [active_sig_index, parameter_length]
        end

        active_parameter_index = flat_arguments.find_index do |argument|
          (argument.location.start_offset..argument.location.end_offset).cover?(@char_position)
        end || parameter_length

        # If there's a trailing comma after the end of the current argument,
        # advance the active parameter to the next one
        if node.slice.byteslice(@char_position - node.location.start_offset) == ","
          active_parameter_index += 1
        end

        # if the incoming position is a keyword parameter,
        # find the first keyword that is not in the current argument list
        if signature && keyword_parameter?(signature.parameters[active_parameter_index])
          active_parameter_index = determine_active_keyword_argument(signature, flat_arguments)
        end

        [active_sig_index, active_parameter_index]
      end

      #: (RubyIndexer::Entry::Signature active_signature, Array[Prism::Node] arguments) -> Integer
      def determine_active_keyword_argument(active_signature, arguments)
        arg_names = T.cast(
          arguments.select { _1.is_a?(Prism::AssocNode) },
          T::Array[Prism::AssocNode],
        ).map do |arg|
          key = arg.key
          arg_name =
            case key
            when Prism::StringNode then key.content
            when Prism::SymbolNode then key.value
            when Prism::CallNode then key.name
            end

          arg_name&.to_sym
        end.compact
        active_signature.parameters.find_index do |param|
          keyword_parameter?(param) && !arg_names.include?(param.name)
        end || active_signature.parameters.length
      end

      #: (Array[RubyIndexer::Entry::Signature] signatures, String method_name, Array[RubyIndexer::Entry] methods, String title, String? extra_links) -> Array[Interface::SignatureInformation]
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

      #: (RubyIndexer::Entry::Parameter?) -> bool
      def keyword_parameter?(param)
        !param.nil? && (param.is_a?(RubyIndexer::Entry::KeywordParameter) ||
          param.is_a?(RubyIndexer::Entry::OptionalKeywordParameter))
      end
    end
  end
end
