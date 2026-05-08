# typed: strict
# frozen_string_literal: true

module Rubydex
  # @abstract
  class Declaration
    # Detail text shown on a `TypeHierarchyItem` for this declaration. Hints at multiplicity
    # when the declaration spans more than one re-open; otherwise falls back to the primary
    # definition's file name so users can quickly see where the type comes from.
    #
    #: -> String?
    def lsp_type_hierarchy_detail
      defs = definitions
      count = defs.count
      return "#{count} definitions" if count > 1

      primary = defs.first
      return unless primary

      uri = URI(primary.location.uri)
      path = uri.full_path
      path ? File.basename(path) : uri.to_s
    end

    # @abstract
    #: -> Integer
    def to_lsp_completion_kind
      raise RubyLsp::AbstractMethodInvokedError
    end
  end

  # @abstract
  class Namespace
    # Resolved, deduplicated direct supertypes across every re-open of this declaration.
    # Aggregates each definition's own `superclass`/`include`/`prepend` references and drops
    # unresolved ones. Order is stable (first-seen across definitions).
    #: -> Array[Rubydex::Namespace]
    def direct_supertypes
      seen = {} #: Hash[String, Rubydex::Namespace]

      definitions.each do |definition|
        definition.direct_supertype_references.each do |ref|
          next unless ref.is_a?(ResolvedConstantReference)

          target = ref.declaration
          next unless target.is_a?(Namespace)
          next if seen.key?(target.name)

          seen[target.name] = target
        end
      end

      seen.values
    end
  end

  class Class
    # @override
    #: -> Integer
    def to_lsp_completion_kind
      RubyLsp::Constant::CompletionItemKind::CLASS
    end
  end

  class Module
    # @override
    #: -> Integer
    def to_lsp_completion_kind
      RubyLsp::Constant::CompletionItemKind::MODULE
    end
  end

  class SingletonClass
    # @override
    #: -> Integer
    def to_lsp_completion_kind
      RubyLsp::Constant::CompletionItemKind::CLASS
    end
  end

  class Todo
    # @override
    #: -> Integer
    def to_lsp_completion_kind
      RubyLsp::Constant::CompletionItemKind::CLASS
    end
  end

  class Constant
    # @override
    #: -> Integer
    def to_lsp_completion_kind
      RubyLsp::Constant::CompletionItemKind::CONSTANT
    end
  end

  class ConstantAlias
    # @override
    #: -> Integer
    def to_lsp_completion_kind
      RubyLsp::Constant::CompletionItemKind::CONSTANT
    end
  end

  class Method
    # @override
    #: -> Integer
    def to_lsp_completion_kind
      RubyLsp::Constant::CompletionItemKind::METHOD
    end
  end

  class InstanceVariable
    # @override
    #: -> Integer
    def to_lsp_completion_kind
      RubyLsp::Constant::CompletionItemKind::FIELD
    end
  end

  class ClassVariable
    # @override
    #: -> Integer
    def to_lsp_completion_kind
      RubyLsp::Constant::CompletionItemKind::FIELD
    end
  end

  class GlobalVariable
    # @override
    #: -> Integer
    def to_lsp_completion_kind
      RubyLsp::Constant::CompletionItemKind::VARIABLE
    end
  end
end
