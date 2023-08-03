# typed: strict
# frozen_string_literal: true

module RubyLsp
  module Requests
    module Support
      module FormatterRunner
        extend T::Sig
        extend T::Helpers

        interface!

        sig { abstract.params(uri: URI::Generic, document: Document).returns(T.nilable(String)) }
        def run(uri, document); end
      end
    end
  end
end
