# typed: strict
# frozen_string_literal: true

module RubyLsp
  module Requests
    # ![Code actions demo](../../misc/code_actions.gif)
    #
    # The [code actions](https://microsoft.github.io/language-server-protocol/specification#textDocument_codeAction)
    # request informs the editor of RuboCop quick fixes that can be applied. These are accesible by hovering over a
    # specific diagnostic.
    #
    # # Example
    #
    # ```ruby
    # def say_hello
    # puts "Hello" # --> code action: quick fix indentation
    # end
    # ```
    class CodeActionResolve < BaseRequest
      extend T::Sig

      sig do
        params(document: Document,
          code_action: { title: String, kind: String, data: T::Hash[Symbol, T.untyped], isPreferred: T::Boolean })
          .void
      end
      def initialize(document, code_action)
        super(document)
        @code_action = code_action
      end

      sig { override.returns(Interface::CodeAction) }
      def run
        to_quick_fix
      end

      private

      sig { returns(Interface::CodeAction) }
      def to_quick_fix
        Interface::CodeAction.new(
          title: @code_action[:title],
          kind: @code_action[:kind],
          is_preferred: @code_action[:isPreferred],
          edit: @code_action.dig(:data, :edit),
        )
      end
    end
  end
end
