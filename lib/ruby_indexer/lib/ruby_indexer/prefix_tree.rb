# typed: true
# frozen_string_literal: true

require "set"

module RubyIndexer
  # A PrefixTree is a data structure that allows searching for partial strings fast. Instead of using a character-level
  # trie (which creates one node per character and is very memory-intensive), this implementation uses a sorted array
  # with binary search for memory-efficient prefix matching.
  #
  # ## Example
  # ```ruby
  # tree = PrefixTree[String].new
  # # Insert entries using the same key and value
  # tree.insert("bar", "bar")
  # tree.insert("baz", "baz")
  # # When we search it, it finds all possible values based on partial (or complete matches):
  # tree.search("") # => ["bar", "baz"]
  # tree.search("b") # => ["bar", "baz"]
  # tree.search("ba") # => ["bar", "baz"]
  # tree.search("bar") # => ["bar"]
  # ```
  #
  # A PrefixTree is useful for autocomplete, since we always want to find all alternatives while the developer hasn't
  # finished typing yet. This PrefixTree implementation allows for string keys and any arbitrary value using the generic
  # `Value` type.
  #
  # See https://en.wikipedia.org/wiki/Trie for more information
  #: [Value]
  class PrefixTree
    # Creates a new PrefixTree. If `external_store` is provided, the tree uses that hash for value storage and lookups
    # instead of maintaining its own internal hash. This avoids duplicating data when the caller already maintains a
    # hash with the same key-value mapping. The caller is responsible for populating the external store; the tree only
    # tracks which keys exist for prefix searching.
    #: (?Hash[String, Value]? external_store) -> void
    def initialize(external_store = nil)
      @external = external_store #: Hash[String, Value]?
      @values = external_store || {} #: Hash[String, Value]
      @sorted_keys = [] #: Array[String]
      @tracked_keys = Set.new #: Set[String]
      @dirty = false #: bool
    end

    # Search the PrefixTree based on a given `prefix`. If `foo` is an entry in the tree, then searching for `fo` will
    # return it as a result. The result is always an array of the type of value attribute to the generic `Value` type.
    # Notice that if the `Value` is an array, this method will return an array of arrays, where each entry is the array
    # of values for a given match
    #: (String prefix) -> Array[Value]
    def search(prefix)
      if prefix.empty?
        return @values.values
      end

      ensure_sorted!

      # Binary search to find the first key >= prefix
      idx = @sorted_keys.bsearch_index { |k| k >= prefix }
      return [] unless idx

      results = []
      len = @sorted_keys.length

      while idx < len
        key = @sorted_keys[idx]
        break unless key.start_with?(prefix)

        val = @values[key] #: Value?
        results << val if val
        idx += 1
      end

      results
    end

    # Inserts a `value` using the given `key`
    #: (String key, Value value) -> void
    def insert(key, value)
      unless @tracked_keys.include?(key)
        @sorted_keys << key
        @tracked_keys << key
        @dirty = true
      end

      # When using an external store, the caller manages the values directly.
      # Otherwise, store it in our internal hash.
      @values[key] = value unless @external
    end

    # Deletes the entry identified by `key` from the tree. Notice that a partial match will still delete all entries
    # that match it. For example, if the tree contains `foo` and we ask to delete `fo`, then `foo` will be deleted
    #: (String key) -> void
    def delete(key)
      # Check for exact match first (most common case)
      if @tracked_keys.include?(key)
        @values.delete(key) unless @external
        @tracked_keys.delete(key)
        @sorted_keys.delete(key)
        return
      end

      # Handle partial prefix match: delete all entries whose key starts with the given prefix
      ensure_sorted!

      idx = @sorted_keys.bsearch_index { |k| k >= key }
      return unless idx

      keys_to_delete = []
      len = @sorted_keys.length

      while idx < len
        k = @sorted_keys[idx]
        break unless k.start_with?(key)

        keys_to_delete << k
        idx += 1
      end

      keys_to_delete.each do |k|
        @values.delete(k) unless @external
        @tracked_keys.delete(k)
      end

      # Rebuild sorted_keys from tracked keys (more efficient than multiple deletes)
      if keys_to_delete.any?
        @sorted_keys = @tracked_keys.to_a
        @dirty = true
      end
    end

    private

    #: -> void
    def ensure_sorted!
      if @dirty
        @sorted_keys.sort!
        @dirty = false
      end
    end

    # Keep the Node class for backwards compatibility with any external consumers, but it's no longer used internally
    #: [Value]
    class Node
      #: Hash[String, Node[Value]]
      attr_reader :children

      #: String
      attr_reader :key

      #: Value
      attr_accessor :value

      #: bool
      attr_accessor :leaf

      #: Node[Value]?
      attr_reader :parent

      #: (String key, Value value, ?Node[Value]? parent) -> void
      def initialize(key, value, parent = nil)
        @key = key
        @value = value
        @parent = parent
        @children = {}
        @leaf = false
      end

      #: -> Array[Value]
      def collect
        result = []
        stack = [self]

        while (node = stack.pop)
          result << node.value if node.leaf
          stack.concat(node.children.values)
        end

        result
      end
    end
  end
end
