# typed: strict
# frozen_string_literal: true

return unless defined?(RubyLsp::Requests::Support::RuboCopRunner)

require "ruby_lsp/requests/support/rubocop_diagnostic"

module RubyLsp
  module Requests
    module Support
      class RuboCopFormatter
        include Formatter

        #: -> void
        def initialize
          @diagnostic_runner = RuboCopRunner.new #: RuboCopRunner
          # -a is for "--auto-correct" (or "--autocorrect" on newer versions of RuboCop)
          @format_runner = RuboCopRunner.new("-a") #: RuboCopRunner
        end

        # @override
        #: (URI::Generic uri, RubyDocument document) -> String?
        def run_formatting(uri, document)
          filename = uri.to_standardized_path || uri.opaque #: as !nil

          # Invoke RuboCop with just this file in `paths`
          @format_runner.run(filename, document.source)
          @format_runner.formatted_source
        end

        # RuboCop does not support range formatting
        # @override
        #: (URI::Generic uri, String source, Integer base_indentation) -> String?
        def run_range_formatting(uri, source, base_indentation)
          nil
        end

        # @override
        #: (URI::Generic uri, RubyDocument document) -> Array[Interface::Diagnostic]?
        def run_diagnostic(uri, document)
          filename = uri.to_standardized_path || uri.opaque #: as !nil
          # Invoke RuboCop with just this file in `paths`
          @diagnostic_runner.run(filename, document.source)

          @diagnostic_runner.offenses.map do |offense|
            Support::RuboCopDiagnostic.new(
              document,
              offense,
              uri,
            ).to_lsp_diagnostic(@diagnostic_runner.config_for_working_directory)
          end
        end
      end
    end
  end
end
