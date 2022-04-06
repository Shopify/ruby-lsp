# frozen_string_literal: true

require "rubocop"
require "cgi"

module RubyLsp
  module Requests
    class RuboCopRequest < RuboCop::Runner
      attr_reader :uri, :file, :text

      def self.run(uri, parsed_tree)
        new(uri, parsed_tree).run
      end

      def initialize(uri, parsed_tree)
        @file = CGI.unescape(URI.parse(uri).path)
        @text = parsed_tree.source

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
        [
          "--stderr", # Print any output to stderr so that our stdout does not get polluted
          "--format",
          "RuboCop::Formatter::BaseFormatter", # Suppress any output by using the base formatter
        ]
      end
    end
  end
end
