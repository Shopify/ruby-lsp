# typed: strict
# frozen_string_literal: true

module Rubydex
  # @abstract
  class Definition
    #: () -> RubyLsp::Interface::LocationLink
    def to_lsp_location_link
      selection_range = to_lsp_selection_range

      RubyLsp::Interface::LocationLink.new(
        target_uri: location.uri,
        target_range: selection_range,
        target_selection_range: to_lsp_name_range || selection_range,
      )
    end

    # @abstract
    #: () -> Integer
    def to_lsp_kind
      raise RubyLsp::AbstractMethodInvokedError
    end

    # Direct ancestor references contributed by this definition (superclass, includes, prepends).
    # Extends are intentionally excluded here because they extend the singleton class, not the
    # instance-side ancestor chain. Definition subclasses that can't contribute ancestors return [].
    #: () -> Array[Rubydex::ConstantReference]
    def direct_supertype_references
      []
    end

    #: (String name, ?detail: String?) -> RubyLsp::Interface::TypeHierarchyItem
    def to_lsp_type_hierarchy_item(name, detail: nil)
      range = to_lsp_selection_range

      RubyLsp::Interface::TypeHierarchyItem.new(
        name: name,
        kind: to_lsp_kind,
        uri: location.uri,
        range: range,
        selection_range: to_lsp_name_range || range,
        detail: detail,
        data: { fully_qualified_name: name },
      )
    end

    #: (String name) -> RubyLsp::Interface::WorkspaceSymbol
    def to_lsp_workspace_symbol(name)
      # We use the namespace as the container name, but we also use the full name as the regular name. The reason we do
      # this is to allow people to search for fully qualified names (e.g.: `Foo::Bar`). If we only included the short
      # name `Bar`, then searching for `Foo::Bar` would not return any results
      *container, _short_name = name.split("::")
      container_name = container.join("::")

      RubyLsp::Interface::WorkspaceSymbol.new(
        name: name,
        container_name: container_name,
        kind: to_lsp_kind,
        location: to_lsp_selection_location,
      )
    end

    #: () -> RubyLsp::Interface::Range
    def to_lsp_selection_range
      loc = location

      RubyLsp::Interface::Range.new(
        start: RubyLsp::Interface::Position.new(line: loc.start_line, character: loc.start_column),
        end: RubyLsp::Interface::Position.new(line: loc.end_line, character: loc.end_column),
      )
    end

    #: () -> RubyLsp::Interface::Location
    def to_lsp_selection_location
      location = self.location

      RubyLsp::Interface::Location.new(
        uri: location.uri,
        range: RubyLsp::Interface::Range.new(
          start: RubyLsp::Interface::Position.new(line: location.start_line, character: location.start_column),
          end: RubyLsp::Interface::Position.new(line: location.end_line, character: location.end_column),
        ),
      )
    end

    #: () -> RubyLsp::Interface::Range?
    def to_lsp_name_range
      loc = name_location
      return unless loc

      RubyLsp::Interface::Range.new(
        start: RubyLsp::Interface::Position.new(line: loc.start_line, character: loc.start_column),
        end: RubyLsp::Interface::Position.new(line: loc.end_line, character: loc.end_column),
      )
    end

    #: () -> RubyLsp::Interface::Location?
    def to_lsp_name_location
      location = name_location
      return unless location

      RubyLsp::Interface::Location.new(
        uri: location.uri,
        range: RubyLsp::Interface::Range.new(
          start: RubyLsp::Interface::Position.new(line: location.start_line, character: location.start_column),
          end: RubyLsp::Interface::Position.new(line: location.end_line, character: location.end_column),
        ),
      )
    end
  end

  # Shared supertype aggregation for Rubydex definition types that carry namespace mixins
  # (`ClassDefinition`, `ModuleDefinition`, `SingletonClassDefinition`). The including class is
  # expected to provide `#mixins`, which every Rubydex namespace definition already does.
  # @abstract
  module NamespaceDefinition
    # @abstract
    #: () -> Array[Rubydex::Mixin]
    def mixins
      raise RubyLsp::AbstractMethodInvokedError
    end

    #: () -> Array[Rubydex::ConstantReference]
    def direct_supertype_references
      mixins.filter_map do |mixin|
        mixin.constant_reference if mixin.is_a?(Include) || mixin.is_a?(Prepend)
      end
    end
  end

  class ClassDefinition
    include NamespaceDefinition

    # @override
    #: () -> Integer
    def to_lsp_kind
      RubyLsp::Constant::SymbolKind::CLASS
    end

    # @override
    #: () -> Array[Rubydex::ConstantReference]
    def direct_supertype_references
      refs = super
      superclass_ref = superclass
      refs << superclass_ref if superclass_ref
      refs
    end
  end

  class ModuleDefinition
    include NamespaceDefinition

    # @override
    #: () -> Integer
    def to_lsp_kind
      RubyLsp::Constant::SymbolKind::NAMESPACE
    end
  end

  class SingletonClassDefinition
    include NamespaceDefinition

    # @override
    #: () -> Integer
    def to_lsp_kind
      RubyLsp::Constant::SymbolKind::CLASS
    end
  end

  class ConstantDefinition
    # @override
    #: () -> Integer
    def to_lsp_kind
      RubyLsp::Constant::SymbolKind::CONSTANT
    end
  end

  class ConstantAliasDefinition
    # @override
    #: () -> Integer
    def to_lsp_kind
      RubyLsp::Constant::SymbolKind::CONSTANT
    end
  end

  class ConstantVisibilityDefinition
    # @override
    #: () -> Integer
    def to_lsp_kind
      RubyLsp::Constant::SymbolKind::CONSTANT
    end
  end

  class MethodDefinition
    # @override
    #: () -> Integer
    def to_lsp_kind
      name == "initialize()" ? RubyLsp::Constant::SymbolKind::CONSTRUCTOR : RubyLsp::Constant::SymbolKind::METHOD
    end
  end

  class MethodAliasDefinition
    # @override
    #: () -> Integer
    def to_lsp_kind
      RubyLsp::Constant::SymbolKind::METHOD
    end
  end

  class MethodVisibilityDefinition
    # @override
    #: () -> Integer
    def to_lsp_kind
      RubyLsp::Constant::SymbolKind::METHOD
    end
  end

  class AttrReaderDefinition
    # @override
    #: () -> Integer
    def to_lsp_kind
      RubyLsp::Constant::SymbolKind::PROPERTY
    end
  end

  class AttrWriterDefinition
    # @override
    #: () -> Integer
    def to_lsp_kind
      RubyLsp::Constant::SymbolKind::PROPERTY
    end
  end

  class AttrAccessorDefinition
    # @override
    #: () -> Integer
    def to_lsp_kind
      RubyLsp::Constant::SymbolKind::PROPERTY
    end
  end

  class InstanceVariableDefinition
    # @override
    #: () -> Integer
    def to_lsp_kind
      RubyLsp::Constant::SymbolKind::FIELD
    end
  end

  class ClassVariableDefinition
    # @override
    #: () -> Integer
    def to_lsp_kind
      RubyLsp::Constant::SymbolKind::FIELD
    end
  end

  class GlobalVariableDefinition
    # @override
    #: () -> Integer
    def to_lsp_kind
      RubyLsp::Constant::SymbolKind::VARIABLE
    end
  end

  class GlobalVariableAliasDefinition
    # @override
    #: () -> Integer
    def to_lsp_kind
      RubyLsp::Constant::SymbolKind::VARIABLE
    end
  end
end
