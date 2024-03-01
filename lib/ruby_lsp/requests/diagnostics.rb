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
    class Diagnostics < Request
      extend T::Sig

      class << self
        extend T::Sig

        sig { returns(T::Hash[Symbol, T::Boolean]) }
        def provider
          {
            interFileDependencies: false,
            workspaceDiagnostics: false,
          }
        end
      end

      sig { params(document: Document).void }
      def initialize(document)
        super()
        @document = document
        @uri = T.let(document.uri, URI::Generic)
      end

      sig { override.returns(T.nilable(T.all(T::Array[Interface::Diagnostic], Object))) }
      def perform
        diagnostics = []
        diagnostics.concat(syntax_error_diagnostics, syntax_warning_diagnostics)

        # Running RuboCop is slow, so to avoid excessive runs we only do so if the file is syntactically valid
        return diagnostics if @document.syntax_error?

        diagnostics.concat(
          Support::RuboCopDiagnosticsRunner.instance.run(
            @uri,
            @document,
          ).map!(&:to_lsp_diagnostic),
        ) if defined?(Support::RuboCopDiagnosticsRunner)

        diagnostics
      end

      private

      sig { returns(T::Array[Interface::Diagnostic]) }
      def syntax_warning_diagnostics
        @document.parse_result.warnings.map do |warning|
          location = warning.location

          Interface::Diagnostic.new(
            source: "Prism",
            message: warning.message,
            severity: Constant::DiagnosticSeverity::WARNING,
            range: Interface::Range.new(
              start: Interface::Position.new(
                line: location.start_line - 1,
                character: location.start_column,
              ),
              end: Interface::Position.new(
                line: location.end_line - 1,
                character: location.end_column,
              ),
            ),
          )
        end
      end

      sig { returns(T::Array[Interface::Diagnostic]) }
      def syntax_error_diagnostics
        @document.parse_result.errors.map do |error|
          location = error.location

          Interface::Diagnostic.new(
            range: Interface::Range.new(
              start: Interface::Position.new(
                line: location.start_line - 1,
                character: location.start_column,
              ),
              end: Interface::Position.new(
                line: location.end_line - 1,
                character: location.end_column,
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
