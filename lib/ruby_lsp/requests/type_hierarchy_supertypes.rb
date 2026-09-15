# typed: strict
# frozen_string_literal: true

module RubyLsp
  module Requests
    # The [type hierarchy supertypes
    # request](https://microsoft.github.io/language-server-protocol/specification#typeHierarchy_supertypes)
    # displays the list of ancestors (supertypes) for the selected type.
    class TypeHierarchySupertypes < Request
      include Support::Common

      #: (GlobalState, Hash[Symbol, untyped]) -> void
      def initialize(global_state, item)
        super()

        @graph = global_state.graph #: Rubydex::Graph
        @item = item
      end

      # @override
      #: -> Array[Interface::TypeHierarchyItem]?
      def perform
        fully_qualified_name = @item.dig(:data, :fully_qualified_name) || @item[:name] #: String?
        return unless fully_qualified_name

        declaration = @graph[fully_qualified_name]
        return unless declaration.is_a?(Rubydex::Namespace)

        compute_supertypes(declaration).filter_map { |name, backing| hierarchy_item(name, backing) }
      end

      private

      # Returns an array of `[display_name, backing_declaration]` pairs. `display_name` is the name shown in the type
      # hierarchy item (which may be a synthesized singleton class name like `Object::<Object>`). `backing_declaration`
      # is the namespace whose primary definition provides the location for the hierarchy item — it may differ from the
      # display name when the singleton class is implicit and has no definitions of its own, in which case we fall back
      # to the attached object's definition so the user still lands somewhere useful.
      #
      #: (Rubydex::Namespace) -> Array[[String, Rubydex::Namespace]]
      def compute_supertypes(declaration)
        case declaration
        when Rubydex::SingletonClass
          singleton_supertypes(declaration)
        when Rubydex::Class
          class_supertypes(declaration)
        else
          explicit_supertypes(declaration)
        end
      end

      #: (Rubydex::Class) -> Array[[String, Rubydex::Namespace]]
      def class_supertypes(declaration)
        # `BasicObject` is the root of the Ruby class hierarchy
        supertypes = explicit_supertypes(declaration)
        return supertypes if declaration.name == "BasicObject"

        # If the class has any superclass reference (resolved or unresolved), don't re-add the implicit `Object`.
        has_superclass = declaration.definitions.any? do |d|
          d.is_a?(Rubydex::ClassDefinition) && !d.superclass.nil?
        end
        return supertypes if has_superclass

        object = @graph["Object"] #: as Rubydex::Namespace
        supertypes << ["Object", object]
        supertypes
      end

      #: (Rubydex::Namespace) -> Array[[String, Rubydex::Namespace]]
      def explicit_supertypes(declaration)
        declaration.direct_supertypes.map { |s| [s.name, s] }
      end

      # Singleton classes don't have their own superclass references. Their direct supertype is the singleton class of
      # the attached object's superclass, computed recursively so that nested singleton classes (e.g.
      # `Foo::<Foo>::<<Foo>>`) still resolve to the matching depth on the parent chain. When the synthesized singleton
      # class name has no backing declaration with definitions (implicit singleton), we fall back to the attached
      # supertype's backing so the user is still navigated to a meaningful location.
      #
      #: (Rubydex::SingletonClass) -> Array[[String, Rubydex::Namespace]]
      def singleton_supertypes(declaration)
        attached = declaration.owner
        return [] unless attached.is_a?(Rubydex::Namespace)

        compute_supertypes(attached).map do |parent_name, parent_backing|
          singleton_name = singleton_name_of(parent_name)
          found = @graph[singleton_name]
          backing = found.is_a?(Rubydex::Namespace) && found.definitions.any? ? found : parent_backing
          [singleton_name, backing]
        end
      end

      #: (String) -> String
      def singleton_name_of(name)
        unqualified = name.split("::").last || name
        "#{name}::<#{unqualified}>"
      end

      #: (String, Rubydex::Namespace) -> Interface::TypeHierarchyItem?
      def hierarchy_item(name, declaration)
        primary = declaration.definitions.first #: Rubydex::Definition?
        return unless primary

        primary.to_lsp_type_hierarchy_item(
          name,
          detail: declaration.lsp_type_hierarchy_detail,
        )
      end
    end
  end
end
