# typed: strict
# frozen_string_literal: true

return unless defined?(RubyLsp::Requests::Support::RuboCopRunner)

require "ruby_lsp/requests/support/rubocop_diagnostic"

module RubyLsp
  module Requests
    module Support
      class RuboCopFormatter
        extend T::Sig
        include Formatter

        sig { void }
        def initialize
          @diagnostic_runner = T.let(RuboCopRunner.new, RuboCopRunner)
          # -a is for "--auto-correct" (or "--autocorrect" on newer versions of RuboCop)
          @format_runner = T.let(RuboCopRunner.new("-a"), RuboCopRunner)
        end

        sig { override.params(uri: URI::Generic, document: RubyDocument).returns(T.nilable(String)) }
        def run_formatting(uri, document)
          filename = T.must(uri.to_standardized_path || uri.opaque)

          # Invoke RuboCop with just this file in `paths`
          @format_runner.run(filename, document.source)
          @format_runner.formatted_source
        end

        # RuboCop does not support range formatting
        sig { override.params(uri: URI::Generic, source: String, base_indentation: Integer).returns(T.nilable(String)) }
        def run_range_formatting(uri, source, base_indentation)
          nil
        end

        sig do
          override.params(
            uri: URI::Generic,
            document: RubyDocument,
          ).returns(T.nilable(T::Array[Interface::Diagnostic]))
        end
        def run_diagnostic(uri, document)
          filename = T.must(uri.to_standardized_path || uri.opaque)
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
