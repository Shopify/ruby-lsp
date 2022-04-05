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
        @formatted_text = nil

        super(
          ::RuboCop::Options.new.parse(self.class::RUBOCOP_FLAGS).first,
          ::RuboCop::ConfigStore.new
        )
      end

      def run(file_paths)
        super
      end
    end
  end
end
