# typed: strict
# frozen_string_literal: true

module RubyLsp
  module Requests
    # The [type hierarchy supertypes
    # request](https://microsoft.github.io/language-server-protocol/specification#typeHierarchy_supertypes)
    # displays the list of ancestors (supertypes) for the selected type.
    class TypeHierarchySupertypes < Request
      include Support::Common

      #: (RubyIndexer::Index index, Hash[Symbol, untyped] item) -> void
      def initialize(index, item)
        super()

        @index = index
        @item = item
      end

      # @override
      #: -> Array[Interface::TypeHierarchyItem]?
      def perform
        name = @item[:name]
        entries = @index[name]

        parents = Set.new #: Set[RubyIndexer::Entry::Namespace]
        return unless entries&.any?

        entries.each do |entry|
          next unless entry.is_a?(RubyIndexer::Entry::Namespace)

          if entry.is_a?(RubyIndexer::Entry::Class)
            parent_class_name = entry.parent_class
            if parent_class_name
              resolved_parent_entries = @index.resolve(parent_class_name, entry.nesting)
              resolved_parent_entries&.each do |entry|
                next unless entry.is_a?(RubyIndexer::Entry::Class)

                parents << entry
              end
            end
          end

          entry.mixin_operations.each do |mixin_operation|
            mixin_name = mixin_operation.module_name
            resolved_mixin_entries = @index.resolve(mixin_name, entry.nesting)
            next unless resolved_mixin_entries

            resolved_mixin_entries.each do |mixin_entry|
              next unless mixin_entry.is_a?(RubyIndexer::Entry::Module)

              parents << mixin_entry
            end
          end
        end

        parents.map { |entry| hierarchy_item(entry) }
      end

      private

      #: (RubyIndexer::Entry entry) -> Interface::TypeHierarchyItem
      def hierarchy_item(entry)
        Interface::TypeHierarchyItem.new(
          name: entry.name,
          kind: kind_for_entry(entry),
          uri: entry.uri.to_s,
          range: range_from_location(entry.location),
          selection_range: range_from_location(entry.name_location),
          detail: entry.file_name,
        )
      end
    end
  end
end
