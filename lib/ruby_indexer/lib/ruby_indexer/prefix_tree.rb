# typed: true
# frozen_string_literal: true

module RubyIndexer
  # A PrefixTree is a data structure that allows searching for partial strings fast. The tree is similar to a nested
  # hash structure, where the keys are the characters of the inserted strings. Chains of nodes that have a single child
  # and no value of their own are compressed into a single node (a radix tree), which drastically reduces the number of
  # objects needed to represent large sets of keys.
  #
  # ## Example
  # ```ruby
  # tree = PrefixTree[String].new
  # # Insert entries using the same key and value
  # tree.insert("bar", "bar")
  # tree.insert("baz", "baz")
  # # Internally, the structure is analogous to this, but using nodes:
  # # {
  # #   "ba" => {
  # #     "r" => "bar",
  # #     "z" => "baz"
  # #   }
  # # }
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
    #: -> void
    def initialize
      @root = Node.new("") #: Node[Value]
    end

    # Search the PrefixTree based on a given `prefix`. If `foo` is an entry in the tree, then searching for `fo` will
    # return it as a result. The result is always an array of the type of value attribute to the generic `Value` type.
    # Notice that if the `Value` is an array, this method will return an array of arrays, where each entry is the array
    # of values for a given match
    #: (String prefix) -> Array[Value]
    def search(prefix)
      node = find_node(prefix)
      return [] unless node

      node.collect
    end

    # Inserts a `value` using the given `key`
    #: (String key, Value value) -> void
    def insert(key, value)
      node = find_or_create_node(key)

      # This line is to allow a value to be overridden. When we are indexing files, we want to be able to update entries
      # for a given fully qualified name if we find more occurrences of it. Without being able to override, that would
      # not be possible
      node.value = value
      node.leaf = true
    end

    # Deletes the entry identified by `key` from the tree. Notice that a partial match will still delete all entries
    # that match it. For example, if the tree contains `foo` and we ask to delete `fo`, then `foo` will be deleted
    #: (String key) -> void
    def delete(key)
      node = find_node(key)
      return unless node

      # Remove the node from the tree and then go up the parents to remove any of them with empty children
      parent = node.parent #: Node[Value]?

      while parent
        parent.children.delete(
          node.key[0], #: as !nil
        )
        return if parent.children.any? || parent.leaf

        node = parent
        parent = parent.parent
      end
    end

    private

    # Walks the tree following `key`, creating (or splitting) nodes as needed, and returns the node where `key` ends
    #: (String key) -> Node[Value]
    def find_or_create_node(key)
      node = @root
      remaining = key

      until remaining.empty?
        first_char = remaining[0] #: as !nil
        child = node.child(first_char)

        unless child
          # No edge starts with this character, so the entire remainder of the key becomes a single new node
          new_node = Node.new(remaining, node)
          node.children[first_char] = new_node
          return new_node
        end

        label = child.key
        common = common_prefix_length(label, remaining)

        if common < label.length
          # The key diverges in the middle of an existing edge, so we split it. The new intermediate node takes the place
          # of the existing child (keeping its position among its siblings) and the existing child is pushed down
          intermediate = Node.new(
            label[0, common], #: as !nil
            node,
          )
          node.children[first_char] = intermediate

          remainder = label[common..] #: as !nil
          child.key = remainder
          child.parent = intermediate
          intermediate.children[
            remainder[0], #: as !nil
          ] = child

          child = intermediate
        end

        node = child
        remaining = remaining[common..] #: as !nil
      end

      node
    end

    # Find the node that contains all keys starting with the given `key`. Because edges are compressed, the match may
    # end in the middle of an edge, in which case the node at the end of that edge is returned
    #: (String key) -> Node[Value]?
    def find_node(key)
      node = @root
      remaining = key

      until remaining.empty?
        child = node.child(
          remaining[0], #: as !nil
        )
        return unless child

        label = child.key

        if remaining.length <= label.length
          return label.start_with?(remaining) ? child : nil
        end

        return unless remaining.start_with?(label)

        remaining = remaining[label.length..] #: as !nil
        node = child
      end

      node
    end

    #: (String a, String b) -> Integer
    def common_prefix_length(a, b)
      max = [a.length, b.length].min
      i = 0
      i += 1 while i < max && a[i] == b[i]
      i
    end

    #: [Value]
    class Node
      #: String
      attr_accessor :key

      #: Value
      attr_accessor :value

      #: bool
      attr_accessor :leaf

      #: Node[Value]?
      attr_accessor :parent

      #: (String key, ?Node[Value]? parent) -> void
      def initialize(key, parent = nil)
        @key = key
        @value = nil #: untyped
        @parent = parent
        # Most nodes are leaves, so we lazily allocate the children hash to avoid paying for an empty hash per node
        @children = nil #: Hash[String, Node[Value]]?
        @leaf = false
      end

      # Children indexed by the first character of their edge label
      #: -> Hash[String, Node[Value]]
      def children
        @children ||= {}
      end

      #: (String char) -> Node[Value]?
      def child(char)
        @children&.[](char)
      end

      #: -> Array[Value]
      def collect
        result = []
        stack = [self]

        while (node = stack.pop)
          result << node.value if node.leaf
          children = node.child_nodes
          stack.concat(children) if children
        end

        result
      end

      #: -> Array[Node[Value]]?
      def child_nodes
        @children&.values
      end
    end
  end
end
