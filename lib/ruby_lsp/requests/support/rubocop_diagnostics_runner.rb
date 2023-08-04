# typed: strict
# frozen_string_literal: true

return unless defined?(RubyLsp::Requests::Support::RuboCopRunner)

require "singleton"

module RubyLsp
  module Requests
    module Support
      # :nodoc:
      class RuboCopDiagnosticsRunner
        extend T::Sig
        include Singleton

        sig { void }
        def initialize
          @runner = T.let(RuboCopRunner.new, RuboCopRunner)
        end

        sig { params(uri: URI::Generic, document: Document).returns(T::Array[Support::RuboCopDiagnostic]) }
        def run(uri, document)
          filename = T.must(uri.to_standardized_path || uri.opaque)
          # Invoke RuboCop with just this file in `paths`
          @runner.run(filename, document.source)

          @runner.offenses.map do |offense|
            Support::RuboCopDiagnostic.new(offense, uri)
          end
        end
      end
    end
  end
end
