# typed: strict
# frozen_string_literal: true

require "ruby_lsp/listeners/signature_help"

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
    class SignatureHelp < Request
      extend T::Sig
      extend T::Generic

      class << self
        extend T::Sig

        sig { returns(Interface::SignatureHelpOptions) }
        def provider
          # Identifier characters are automatically included, such as A-Z, a-z, 0-9, _, * or :
          Interface::SignatureHelpOptions.new(
            trigger_characters: ["(", " ", ","],
          )
        end
      end

      ResponseType = type_member { { fixed: T.nilable(T.any(Interface::SignatureHelp, T::Hash[Symbol, T.untyped])) } }

      sig do
        params(
          document: Document,
          index: RubyIndexer::Index,
          position: T::Hash[Symbol, T.untyped],
          context: T.nilable(T::Hash[Symbol, T.untyped]),
          dispatcher: Prism::Dispatcher,
        ).void
      end
      def initialize(document, index, position, context, dispatcher)
        super()
        current_signature = context && context[:activeSignatureHelp]
        target, parent, nesting = document.locate_node(
          { line: position[:line], character: position[:character] - 2 },
          node_types: [Prism::CallNode],
        )

        # If we're typing a nested method call (e.g.: `foo(bar)`), then we may end up locating `bar` as the target
        # method call incorrectly. To correct that, we check if there's an active signature with the same name as the
        # parent node and then replace the target
        if current_signature && parent.is_a?(Prism::CallNode)
          active_signature = current_signature[:activeSignature] || 0

          if current_signature.dig(:signatures, active_signature, :label)&.start_with?(parent.message)
            target = parent
          end
        end

        @target = T.let(target, T.nilable(Prism::Node))
        @dispatcher = dispatcher
        @listener = T.let(Listeners::SignatureHelp.new(nesting, index, dispatcher), Listener[ResponseType])
      end

      sig { override.returns(ResponseType) }
      def perform
        return unless @target

        @dispatcher.dispatch_once(@target)
        @listener.response
      end
    end
  end
end
