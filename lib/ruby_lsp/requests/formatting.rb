# frozen_string_literal: true

module RubyLsp
  module Requests
    class Formatting < RuboCopRequest
      def run
        super

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

      private

      def rubocop_flags
        [
          "--stderr", # Print any output to stderr so that our stdout does not get polluted
          "--format",
          "RuboCop::Formatter::BaseFormatter", # Suppress any output by using the base formatter
          "--auto-correct", # Apply the autocorrects on the supplied buffer
        ]
      end
    end
  end
end
