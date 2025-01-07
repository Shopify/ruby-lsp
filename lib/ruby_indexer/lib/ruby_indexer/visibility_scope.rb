# typed: strict
# frozen_string_literal: true

module RubyIndexer
  # Represents the visibility scope in a Ruby namespace. This keeps track of whether methods are in a public, private or
  # protected section, and whether they are module functions.
  class VisibilityScope
    extend T::Sig

    class << self
      extend T::Sig

      sig { returns(T.attached_class) }
      def module_function_scope
        new(module_func: true, visibility: Entry::Visibility::PRIVATE)
      end

      sig { returns(T.attached_class) }
      def public_scope
        new
      end
    end

    sig { returns(Entry::Visibility) }
    attr_reader :visibility

    sig { returns(T::Boolean) }
    attr_reader :module_func

    sig { params(visibility: Entry::Visibility, module_func: T::Boolean).void }
    def initialize(visibility: Entry::Visibility::PUBLIC, module_func: false)
      @visibility = visibility
      @module_func = module_func
    end
  end
end
