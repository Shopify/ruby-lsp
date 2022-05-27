# frozen_string_literal: true

module RubyLsp
  module Requests
    module Middleware
      # :nodoc:
      class RuboCop
        def initialize(chain, uri, document)
          @chain = chain
          @uri = uri
          @document = document
          if defined?(Support::RuboCopRunner)
            @runner = Support::RuboCopRunner.new(uri, document)
          end
        end

        def call(diagnostics)
          run(diagnostics)

          @chain.call(diagnostics)
        end

        private

        def run(diagnostics)
          return unless @runner

          @runner.run
          add_offense_diagnostics(diagnostics)
        end

        def add_offense_diagnostics(diagnostics)
          @runner.offenses.map do |offense|
            diagnostics << Support::RuboCopDiagnostic.new(offense, @uri)
          end
        end
      end
    end
  end
end
