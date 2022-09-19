# typed: strict
# frozen_string_literal: true

require "ruby_lsp/requests/support/rubocop_diagnostics_runner"

module RubyLsp
  module Requests
    # ![Diagnostics demo](../../misc/diagnostics.gif)
    #
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

      sig { params(uri: String, document: Document).void }
      def initialize(uri, document)
        super(document)

        @uri = uri
      end

      sig do
        override.returns(
          T.any(
            T.all(T::Array[Support::RuboCopDiagnostic], Object),
            T.all(T::Array[Support::SyntaxErrorDiagnostic], Object),
          ),
        )
      end
      def run
        return syntax_error_diagnostics if @document.syntax_errors?
        return [] unless defined?(Support::RuboCopDiagnosticsRunner)

        Support::RuboCopDiagnosticsRunner.instance.run(@uri, @document)
      end

      private

      sig { returns(T::Array[Support::SyntaxErrorDiagnostic]) }
      def syntax_error_diagnostics
        @document.syntax_error_edits.map { |e| Support::SyntaxErrorDiagnostic.new(e) }
      end
    end
  end
end
