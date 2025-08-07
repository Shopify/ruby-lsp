# typed: strict
# frozen_string_literal: true

module RubyLsp
  module Requests
    module Support
      # Empty module to avoid the runtime component. This is an interface defined in sorbet/rbi/shims/ruby_lsp.rbi
      # @interface
      module Formatter
        # @abstract
        #: (URI::Generic, RubyLsp::RubyDocument) -> String?
        def run_formatting(uri, document)
          raise AbstractMethodInvokedError
        end

        # @abstract
        #: (URI::Generic, String, Integer) -> String?
        def run_range_formatting(uri, source, base_indentation)
          raise AbstractMethodInvokedError
        end

        # @abstract
        #: (URI::Generic, RubyLsp::RubyDocument) -> Array[Interface::Diagnostic]?
        def run_diagnostic(uri, document)
          raise AbstractMethodInvokedError
        end
      end
    end
  end
end
