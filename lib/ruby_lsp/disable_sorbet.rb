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
end
