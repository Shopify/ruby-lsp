# typed: strict
# frozen_string_literal: true

return unless defined?(RubyLsp::Requests::Support::RuboCopRunner)

require "singleton"

module RubyLsp
  module Requests
    module Support
      # :nodoc:
      class RuboCopFormattingRunner
        extend T::Sig
        include Singleton
        include Support::FormatterRunner

        sig { void }
        def initialize
          # -a is for "--auto-correct" (or "--autocorrect" on newer versions of RuboCop)
          @runner = T.let(RuboCopRunner.new("-a"), RuboCopRunner)
        end

        sig { override.params(uri: URI::Generic, document: Document).returns(String) }
        def run(uri, document)
          filename = T.must(uri.to_standardized_path || uri.opaque)

          # Invoke RuboCop with just this file in `paths`
          @runner.run(filename, document.source)

          @runner.formatted_source
        end
      end
    end
  end
end
