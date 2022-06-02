# typed: true
# frozen_string_literal: true

require "rubocop"
require "cgi"

module RubyLsp
  module Requests
    # :nodoc:
    class RuboCopRequest < RuboCop::Runner
      COMMON_RUBOCOP_FLAGS = [
        "--stderr", # Print any output to stderr so that our stdout does not get polluted
        "--format",
        "RuboCop::Formatter::BaseFormatter", # Suppress any output by using the base formatter
      ].freeze

      attr_reader :file, :text

      def self.run(uri, document)
        new(uri, document).run
      end

      def initialize(uri, document)
        @file = CGI.unescape(URI.parse(uri).path)
        @document = document
        @text = document.source
        @uri = uri

        super(
          ::RuboCop::Options.new.parse(rubocop_flags).first,
          ::RuboCop::ConfigStore.new
        )
      end

      def run
        # We communicate with Rubocop via stdin
        @options[:stdin] = text

        # Invoke the actual run method with just this file in `paths`
        super([file])
      end

      private

      def rubocop_flags
        COMMON_RUBOCOP_FLAGS
      end
    end
  end
end
