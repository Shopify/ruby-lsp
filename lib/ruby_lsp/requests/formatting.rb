# frozen_string_literal: true

module RubyLsp
  module Requests
    class Formatting < RuboCopRequest
      RUBOCOP_FLAGS = (COMMON_RUBOCOP_FLAGS + ["--auto-correct"]).freeze

      def initialize(uri, document)
        super
        @formatted_text = nil
      end

      def run
        super

        @formatted_text = @options[:stdin] # Rubocop applies the corrections on stdin
        return unless @formatted_text

        @document&.reset(@formatted_text)

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
        RUBOCOP_FLAGS
      end
    end
  end
end
