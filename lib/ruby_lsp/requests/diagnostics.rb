# typed: strict
# frozen_string_literal: true

module RubyLsp
  module Requests
    # The
    # [diagnostics](https://microsoft.github.io/language-server-protocol/specification#textDocument_publishDiagnostics)
    # request informs the editor of RuboCop offenses for a given file.
    #
    # # Example
    #
    # ```ruby
    # def say_hello
    # puts "Hello" # --> diagnostics: incorrect indentantion
    # end
    # ```
    class Diagnostics < BaseRequest
      extend T::Sig
      include Support::RuboCopRunner::CallbackHandler

      sig { params(uri: String, document: Document).void }
      def initialize(uri, document)
        super(document)

        @uri = uri
        @diagnostics = T.let([], T.any(
          T.all(T::Array[Support::RuboCopDiagnostic], Object),
          T.all(T::Array[Support::SyntaxErrorDiagnostic], Object),
        ))
        @runner = T.let(Support::RuboCopRunner.diagnostics_instance, Support::RuboCopRunner)
      end

      sig do
        override.returns(
          T.any(
            T.all(T::Array[Support::RuboCopDiagnostic], Object),
            T.all(T::Array[Support::SyntaxErrorDiagnostic], Object),
          )
        )
      end
      def run
        if @document.syntax_errors?
          return @document.syntax_error_edits.map { |e| Support::SyntaxErrorDiagnostic.new(e) }
        end

        @runner.run(@uri, @document, self)
        @diagnostics
      end

      sig { override.params(offenses: T::Array[RuboCop::Cop::Offense]).void }
      def callback(offenses)
        @diagnostics = offenses.map { |offense| Support::RuboCopDiagnostic.new(offense, @uri) }
      end
    end
  end
end
