# typed: strict
# frozen_string_literal: true

module RubyLsp
  module Requests
    module Support
      module Formatter
        extend T::Sig
        extend T::Helpers

        interface!

        # @abstract: def run_formatting:(URI::Generic uri, RubyDocument document) -> String?

        # @abstract: def run_range_formatting:(URI::Generic uri, String source, Integer base_indentation) -> String?

        # @abstract: def run_diagnostic:(URI::Generic uri, RubyDocument document) -> Array[Interface::Diagnostic]?
      end
    end
  end
end
