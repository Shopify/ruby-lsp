# frozen_string_literal: true

module RubyLsp
  module Requests
    class BaseRequest < Visitor
      def self.run(parsed_tree)
        new(parsed_tree).run
      end

      def initialize(parsed_tree)
        @parsed_tree = parsed_tree

        super()
      end

      def run
        raise NotImplementedError, "#{self.class}#run must be implemented"
      end
    end
  end
end
