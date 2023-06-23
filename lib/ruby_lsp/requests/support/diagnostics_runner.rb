# typed: strict
# frozen_string_literal: true

module RubyLsp
  module Requests
    module Support
      module DiagnosticsRunner
        extend T::Sig
        extend T::Helpers

        interface!

        sig { abstract.params(uri: String, document: Document).returns(T::Array[Interface::Diagnostic]) }
        def run(uri, document); end
      end
    end
  end
end
