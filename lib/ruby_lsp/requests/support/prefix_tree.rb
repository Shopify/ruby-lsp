# typed: strict
# frozen_string_literal: true

module RubyLsp
  module Requests
    module Support
      class PrefixTree
        extend T::Sig

        sig { params(items: T::Array[String]).void }
        def initialize(items)
          @root = T.let(Node.new(""), Node)

          items.each do |item|
            insert(item)
          end
        end

        sig { params(prefix: String).returns(T::Array[String]) }
        def search(prefix)
          node = T.let(@root, Node)

          prefix.each_char do |char|
            snode = node.children[char]
            return [] unless snode

            node = snode
          end

          node.collect
        end

        private

        sig { params(item: String).void }
        def insert(item)
          node = T.let(@root, Node)

          item.each_char do |char|
            node = node.children[char] ||= Node.new(node.value + char)
          end

          node.leaf = true
        end

        class Node
          extend T::Sig

          sig { returns(T::Hash[String, Node]) }
          attr_reader :children

          sig { returns(String) }
          attr_reader :value

          sig { returns(T::Boolean) }
          attr_accessor :leaf

          sig { params(value: String).void }
          def initialize(value)
            @children = T.let({}, T::Hash[String, Node])
            @value = T.let(value, String)
            @leaf = T.let(false, T::Boolean)
          end

          sig { returns(T::Array[String]) }
          def collect
            result = T.let([], T::Array[String])
            result << value if leaf

            children.each_value do |node|
              result.concat(node.collect)
            end

            result
          end
        end
      end
    end
  end
end
