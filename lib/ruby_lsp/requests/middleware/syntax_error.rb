# frozen_string_literal: true

module RubyLsp
  module Requests
    module Middleware
      # :nodoc:
      class SyntaxError
        def initialize(chain, uri, document)
          @chain = chain
          @uri = uri
          @document = document
        end

        def call(diagnostics)
          return add_syntax_error_diagnostics(diagnostics) if @document.syntax_errors?

          @chain.call(diagnostics)
        end

        private

        def add_syntax_error_diagnostics(diagnostics)
          @document.syntax_error_edits.each do |e|
            diagnostics << Support::SyntaxErrorDiagnostic.new(e)
          end
        end
      end
    end
  end
end
