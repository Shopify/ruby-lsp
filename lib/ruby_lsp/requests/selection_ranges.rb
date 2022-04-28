# frozen_string_literal: true

# Trigger with: Ctrl + Shift + -> or Ctrl + Shift + <-

module RubyLsp
  module Requests
    class SelectionRanges < BaseRequest
      def self.run(document, positions)
        new(document, positions).run
      end

      def initialize(document, positions)
        super(document)
      end

      def run
        [{ response: "Hello, world!" }]
      end
    end
  end
end
