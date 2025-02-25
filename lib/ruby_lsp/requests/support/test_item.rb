# typed: strict
# frozen_string_literal: true

module RubyLsp
  module Requests
    module Support
      # Represents a test item as defined by the VS Code interface to be used in the test explorer
      # See https://code.visualstudio.com/api/references/vscode-api#TestItem
      #
      # Note: this test item object can only represent test groups or examples discovered inside files. It cannot be
      # used to represent test files, directories or workspaces
      class TestItem
        extend T::Sig

        #: String
        attr_reader :id, :label

        #: (String id, String label, URI::Generic uri, Interface::Range range, Array[Symbol] tags) -> void
        def initialize(id, label, uri, range, tags: [])
          @id = id
          @label = label
          @uri = uri
          @range = range
          @tags = tags
          @children = T.let({}, T::Hash[String, TestItem])
        end

        #: (TestItem item) -> void
        def add(item)
          @children[item.id] = item
        end

        #: (String id) -> TestItem?
        def [](id)
          @children[id]
        end

        #: -> Array[TestItem]
        def children
          @children.values
        end

        #: (Symbol) -> bool
        def tag?(tag)
          @tags.include?(tag)
        end

        #: -> Hash[Symbol, untyped]
        def to_hash
          {
            id: @id,
            label: @label,
            uri: @uri,
            range: @range,
            children: children.map(&:to_hash),
          }
        end
      end
    end
  end
end
