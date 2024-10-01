# typed: strict
# frozen_string_literal: true

module RubyLsp
  module Requests
    module Support
      module Formatter
        extend T::Sig
        extend T::Helpers

        interface!

        sig { abstract.params(uri: URI::Generic, document: RubyDocument).returns(T.nilable(String)) }
        def run_formatting(uri, document); end

        sig { abstract.params(uri: URI::Generic, source: String, base_indentation: Integer).returns(T.nilable(String)) }
        def run_range_formatting(uri, source, base_indentation); end

        sig do
          abstract.params(
            uri: URI::Generic,
            document: RubyDocument,
          ).returns(T.nilable(T::Array[Interface::Diagnostic]))
        end
        def run_diagnostic(uri, document); end
      end
    end
  end
end
