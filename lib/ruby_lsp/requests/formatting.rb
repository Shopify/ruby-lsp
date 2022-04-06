# frozen_string_literal: true

require "rubocop"
require "cgi"

module RubyLsp
  module Requests
    class Formatting < RuboCop::Runner
      RUBOCOP_FLAGS = [
        "--stderr", # Print any output to stderr so that our stdout does not get polluted
        "--format",
        "RuboCop::Formatter::BaseFormatter", # Suppress any output by using the base formatter
        "--auto-correct", # Apply the autocorrects on the supplied buffer
      ]

      attr_reader :uri, :file, :text

      def self.run(uri, parsed_tree)
        new(uri, parsed_tree).run
      end

      def initialize(uri, parsed_tree)
        @file = CGI.unescape(URI.parse(uri).path)
        @text = parsed_tree.source
        @formatted_text = nil

        super(
          ::RuboCop::Options.new.parse(RUBOCOP_FLAGS).first,
          ::RuboCop::ConfigStore.new
        )
      end

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
