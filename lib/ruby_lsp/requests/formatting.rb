# frozen_string_literal: true

module RubyLsp
  module Requests
    class Formatting < RuboCopRequest
      RUBOCOP_FLAGS = [
        "--stderr", # Print any output to stderr so that our stdout does not get polluted
        "--format",
        "RuboCop::Formatter::BaseFormatter", # Suppress any output by using the base formatter
        "--auto-correct", # Apply the autocorrects on the supplied buffer
      ].freeze

      def run
        # We communicate with Rubocop via stdin
        @options[:stdin] = text

        # Invoke the actual run method with just this file in `paths`
        super([file])

        @formatted_text = @options[:stdin] # Rubocop applies the corrections on stdin
        return unless @formatted_text

        [
          LanguageServer::Protocol::Interface::TextEdit.new(
            range: LanguageServer::Protocol::Interface::Range.new(
              start: LanguageServer::Protocol::Interface::Position.new(line: 0, character: 0),
              end: LanguageServer::Protocol::Interface::Position.new(
                line: text.size,
                character: text.size
              )
            ),
            new_text: @formatted_text
          ),
        ]
      end
    end
  end
end
