# typed: strict
# frozen_string_literal: true

require "ruby_lsp/requests/support/rubocop_diagnostics_runner"

module RubyLsp
  module Requests
    # ![Diagnostics demo](../../diagnostics.gif)
    #
    # The
    # [diagnostics](https://microsoft.github.io/language-server-protocol/specification#textDocument_publishDiagnostics)
    # request informs the editor of RuboCop offenses for a given file.
    #
    # # Example
    #
    # ```ruby
    # def say_hello
    # puts "Hello" # --> diagnostics: incorrect indentation
    # end
    # ```
    class Diagnostics < BaseRequest
      extend T::Sig

      sig { params(document: Document).void }
      def initialize(document)
        super(document)

        @uri = T.let(document.uri, URI::Generic)
      end

      sig { override.returns(T.nilable(T.all(T::Array[Interface::Diagnostic], Object))) }
      def run
        # Running RuboCop is slow, so to avoid excessive runs we only do so if the file is syntactically valid
        return syntax_error_diagnostics if @document.syntax_error?
        return unless defined?(Support::RuboCopDiagnosticsRunner)

        Support::RuboCopDiagnosticsRunner.instance.run(@uri, @document).map!(&:to_lsp_diagnostic)
      end

      private

      sig { returns(T.nilable(T::Array[Interface::Diagnostic])) }
      def syntax_error_diagnostics
        @document.parse_result.errors.map do |error|
          Interface::Diagnostic.new(
            range: Interface::Range.new(
              start: Interface::Position.new(
                line: error.location.start_line - 1,
                character: error.location.start_column,
              ),
              end: Interface::Position.new(
                line: error.location.end_line - 1,
                character: error.location.end_column,
              ),
            ),
            message: error.message,
            severity: Constant::DiagnosticSeverity::ERROR,
            source: "Prism",
          )
        end
      end
    end
  end
end
