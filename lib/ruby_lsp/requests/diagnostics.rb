# typed: strict
# frozen_string_literal: true

module RubyLsp
  module Requests
    # The
    # [diagnostics](https://microsoft.github.io/language-server-protocol/specification#textDocument_publishDiagnostics)
    # request informs the editor of RuboCop offenses for a given file.
    class Diagnostics < Request
      extend T::Sig

      class << self
        extend T::Sig

        sig { returns(Interface::DiagnosticRegistrationOptions) }
        def provider
          Interface::DiagnosticRegistrationOptions.new(
            document_selector: [Interface::DocumentFilter.new(language: "ruby")],
            inter_file_dependencies: false,
            workspace_diagnostics: false,
          )
        end
      end

      sig { params(global_state: GlobalState, document: RubyDocument).void }
      def initialize(global_state, document)
        super()
        @active_linters = T.let(global_state.active_linters, T::Array[Support::Formatter])
        @document = document
        @uri = T.let(document.uri, URI::Generic)
      end

      sig { override.returns(T.nilable(T.all(T::Array[Interface::Diagnostic], Object))) }
      def perform
        diagnostics = []
        diagnostics.concat(syntax_error_diagnostics, syntax_warning_diagnostics)

        # Running RuboCop is slow, so to avoid excessive runs we only do so if the file is syntactically valid
        if @document.syntax_error? || @active_linters.empty? || @document.past_expensive_limit?
          return diagnostics
        end

        @active_linters.each do |linter|
          linter_diagnostics = linter.run_diagnostic(@uri, @document)
          diagnostics.concat(linter_diagnostics) if linter_diagnostics
        end

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
