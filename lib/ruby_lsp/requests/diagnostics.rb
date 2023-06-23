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

      @diagnostics_runners = T.let(
        {},
        T::Hash[String, Support::DiagnosticsRunner],
      )

      class << self
        extend T::Sig

        sig { returns(T::Hash[String, Support::DiagnosticsRunner]) }
        attr_reader :diagnostics_runners

        sig { params(identifier: String, instance: Support::DiagnosticsRunner).void }
        def register_diagnostic_provider(identifier, instance)
          @diagnostics_runners[identifier] = instance
        end
      end

      if defined?(Support::RuboCopDiagnosticsRunner)
        register_diagnostic_provider("rubocop", Support::RuboCopDiagnosticsRunner.instance)
      end

      sig { params(document: Document).void }
      def initialize(document)
        super(document)

        @uri = T.let(document.uri, String)
      end

      sig { override.returns(T.nilable(T.all(T::Array[Interface::Diagnostic], Object))) }
      def run
        # Running diagnostics is slow, so to avoid excessive runs we only do so if the file is syntactically valid
        return if @document.syntax_error?

        # Don't try to run diagnostics for files outside the current working directory
        return unless URI(@uri).path&.start_with?(T.must(WORKSPACE_URI.path))

        # TODO: Handle configuration for diagnostics runners
        results = []
        Diagnostics.diagnostics_runners.each do |_identifier, runner|
          results.concat(runner.run(@uri, @document))
        end
        results
      end
    end
  end
end
