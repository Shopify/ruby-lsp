# typed: strict
# frozen_string_literal: true

require "ruby_lsp/requests/support/rubocop_diagnostics_runner"
require "ruby_lsp/requests/support/flog_diagnostics_runner"

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

        @uri = T.let(document.uri, String)
      end

      sig { override.returns(T.nilable(T.all(T::Array[Interface::Diagnostic], Object))) }
      def run
        # Running RuboCop is slow, so to avoid excessive runs we only do so if the file is syntactically valid
        return if @document.syntax_error?

        # Don't try to run diagnostics for files outside the current working directory
        return unless URI(@uri).path&.start_with?(T.must(WORKSPACE_URI.path))

        results = []
        if defined?(Support::RuboCopDiagnosticsRunner)
          results.concat(Support::RuboCopDiagnosticsRunner.instance.run(@uri, @document))
        end
        if defined?(Support::FlogDiagnosticsRunner)
          results.concat(Support::FlogDiagnosticsRunner.instance.run(@uri, @document))
        end
        results
      end
    end
  end
end
