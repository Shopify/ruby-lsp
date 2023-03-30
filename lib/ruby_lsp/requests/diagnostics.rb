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

      sig { override.returns(T.nilable(T.all(T::Array[Support::RuboCopDiagnostic], Object))) }
      def run
        return if @document.syntax_error?
        return unless defined?(Support::RuboCopDiagnosticsRunner)

        # Don't try to run RuboCop diagnostics for files outside the current working directory
        return unless @uri.start_with?(WORKSPACE_URI)

        Support::RuboCopDiagnosticsRunner.instance.run(@uri, @document)
      end
    end
  end
end
