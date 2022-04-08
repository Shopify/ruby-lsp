# frozen_string_literal: true

module RubyLsp
  module Requests
    class BaseRequest < Visitor
      def self.run(uri, store)
        store.cache_fetch(uri, self) do
          new(uri, store).run
        end
      end

      def initialize(uri, store)
        @store = store
        @uri = uri
        @parsed_tree = store.get(uri)

        super()
      end

      def run
        raise NotImplementedError, "#{self.class}#run must be implemented"
      end
    end
  end
end
