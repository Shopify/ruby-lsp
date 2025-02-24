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

        sig { returns(String) }
        attr_reader :id, :label

        sig do
          params(id: String, label: String, uri: URI::Generic, range: Interface::Range, tags: T::Array[Symbol]).void
        end
        def initialize(id, label, uri, range, tags: [])
          @id = id
          @label = label
          @uri = uri
          @range = range
          @tags = tags
          @children = T.let({}, T::Hash[String, TestItem])
        end

        sig { params(item: TestItem).void }
        def add(item)
          if @children.key?(item.id)
            raise ResponseBuilders::TestCollection::DuplicateIdError, "TestItem ID is already in use"
          end

          @children[item.id] = item
        end

        sig { params(id: String).returns(T.nilable(TestItem)) }
        def [](id)
          @children[id]
        end

        sig { returns(T::Array[TestItem]) }
        def children
          @children.values
        end

        sig { params(tag: Symbol).returns(T::Boolean) }
        def tag?(tag)
          @tags.include?(tag)
        end

        sig { returns(T::Hash[Symbol, T.untyped]) }
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
