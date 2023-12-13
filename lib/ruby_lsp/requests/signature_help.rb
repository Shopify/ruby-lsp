# typed: strict
# frozen_string_literal: true

module RubyLsp
  module Requests
    # ![Signature help demo](../../signature_help.gif)
    #
    # The [signature help
    # request](https://microsoft.github.io/language-server-protocol/specification#textDocument_signatureHelp) displays
    # information about the parameters of a method as you type an invocation.
    #
    # Currently only supports methods invoked directly on `self` without taking inheritance into account.
    #
    # # Example
    #
    # ```ruby
    # class Foo
    #  def bar(a, b, c)
    #  end
    #
    #  def baz
    #    bar( # -> Signature help will show the parameters of `bar`
    #  end
    # ```
    class SignatureHelp < Listener
      extend T::Sig
      extend T::Generic

      ResponseType = type_member { { fixed: T.nilable(T.any(Interface::SignatureHelp, T::Hash[Symbol, T.untyped])) } }

      sig { override.returns(ResponseType) }
      attr_reader :_response

      sig do
        params(
          context: T::Hash[Symbol, T.untyped],
          nesting: T::Array[String],
          index: RubyIndexer::Index,
          dispatcher: Prism::Dispatcher,
        ).void
      end
      def initialize(context, nesting, index, dispatcher)
        @context = context
        @nesting = nesting
        @index = index
        @_response = T.let(nil, ResponseType)

        super(dispatcher)
        dispatcher.register(self, :on_call_node_enter)
      end

      sig { params(node: Prism::CallNode).void }
      def on_call_node_enter(node)
        return if DependencyDetector.instance.typechecker
        return unless self_receiver?(node)

        message = node.message
        return unless message

        target_method = @index.resolve_method(message, @nesting.join("::"))
        return unless target_method

        parameters = target_method.parameters
        name = target_method.name

        # If the method doesn't have any parameters, there's no need to show signature help
        return if parameters.empty?

        label = "#{name}(#{parameters.map(&:decorated_name).join(", ")})"

        arguments_node = node.arguments
        arguments = arguments_node&.arguments || []
        active_parameter = (arguments.length - 1).clamp(0, parameters.length - 1)

        # If there are arguments, then we need to check if there's a trailing comma after the end of the last argument
        # to advance the active parameter to the next one
        if arguments_node &&
            node.slice.byteslice(arguments_node.location.end_offset - node.location.start_offset) == ","
          active_parameter += 1
        end

        @_response = Interface::SignatureHelp.new(
          signatures: [
            Interface::SignatureInformation.new(
              label: label,
              parameters: parameters.map { |param| Interface::ParameterInformation.new(label: param.name) },
              documentation: markdown_from_index_entries("", target_method),
            ),
          ],
          active_parameter: active_parameter,
        )
      end
    end
  end
end
