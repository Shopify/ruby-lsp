# frozen_string_literal: true

module RubyLsp
  module Requests
    class BaseRequest < SyntaxTree::Visitor
      def self.run(document)
        new(document).run
      end

      def initialize(document)
        @document = document

        super()
      end

      def run
        raise NotImplementedError, "#{self.class}#run must be implemented"
      end
    end
  end
end
