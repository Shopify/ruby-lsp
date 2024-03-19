# typed: true
# frozen_string_literal: true

module RubyLsp
  # No-op all inline type assertions defined in T
  module InlineTypeAssertions
    def cast(value, type, checked: true)
      value
    end

    def let(value, type, checked: true)
      value
    end

    def must(arg)
      arg
    end

    def absurd(value)
      value
    end

    def bind(value, type, checked: true)
      value
    end

    def assert_type!(value, type, checked: true)
      value
    end

    def any(type_a, type_b, *types)
      T::Types::Union.new([type_a, type_b, *types])
    end

    def nilable(type)
      T::Types::Union.new([type, T::Utils::Nilable::NIL_TYPE])
    end

    T.singleton_class.prepend(self)
  end

  # No-op generic type variable syntax
  module TypeVariableSyntax
    def type_member(variance = :invariant, fixed: nil, lower: T.untyped, upper: BasicObject, &block)
      block = TypeVariableSyntax.build_bounds_block(fixed, lower, upper) if block.nil?
      super(variance, &block)
    end

    def type_template(variance = :invariant, fixed: nil, lower: T.untyped, upper: BasicObject, &block)
      block = TypeVariableSyntax.build_bounds_block(fixed, lower, upper) if block.nil?
      super(variance, &block)
    end

    class << self
      def build_bounds_block(fixed, lower, upper)
        bounds = {}
        bounds[:fixed] = fixed unless fixed.nil?
        bounds[:lower] = lower unless lower == T.untyped
        bounds[:upper] = upper unless upper == BasicObject
        -> { bounds }
      end
    end

    T::Generic.prepend(self)
  end
end
