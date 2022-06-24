# typed: strict
# frozen_string_literal: true

module RubyLsp
  module Requests
    # ![Diagnostics demo](../../misc/diagnostics.gif)
    #
    # The
    # [diagnostics](https://microsoft.github.io/language-server-protocol/specification#textDocument_publishDiagnostics)
    # request informs the editor of RuboCop offenses for a given file.
    class Diagnostics < RuboCopRequest
      extend T::Sig

      sig do
        override.returns(
          T.any(
            T.all(T::Array[Support::RuboCopDiagnostic], Object),
            T.all(T::Array[Support::SyntaxErrorDiagnostic], Object),
          )
        )
      end
      def run
        return syntax_error_diagnostics if @document.syntax_errors?

        super

        @diagnostics
      end

      sig { params(_file: String, offenses: T::Array[RuboCop::Cop::Offense]).void }
      def file_finished(_file, offenses)
        @diagnostics = offenses.map { |offense| Support::RuboCopDiagnostic.new(offense, @uri) }
      end

      private

      sig { returns(T::Array[Support::SyntaxErrorDiagnostic]) }
      def syntax_error_diagnostics
        @document.syntax_error_edits.map { |e| Support::SyntaxErrorDiagnostic.new(e) }
      end
    end
  end
end
