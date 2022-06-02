# typed: true
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
    class Diagnostics < RuboCopRequest
      def run
        return syntax_error_diagnostics if @document.syntax_errors?

        super

        @diagnostics
      end

      def file_finished(_file, offenses)
        @diagnostics = offenses.map { |offense| Support::RuboCopDiagnostic.new(offense, @uri) }
      end

      private

      def syntax_error_diagnostics
        @document.syntax_error_edits.map { |e| Support::SyntaxErrorDiagnostic.new(e) }
      end
    end
  end
end
