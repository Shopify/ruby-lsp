# typed: true
# frozen_string_literal: true

require "sorbet-runtime"

begin
  T::Configuration.default_checked_level = :never
  # Suppresses call validation errors
  T::Configuration.call_validation_error_handler = ->(*arg) {}
  # Suppresses errors caused by T.cast, T.let, T.must, etc.
  T::Configuration.inline_type_error_handler = ->(*arg) {}
  # Suppresses errors caused by incorrect parameter ordering
  T::Configuration.sig_validation_error_handler = ->(*arg) {}
rescue
  # Need this rescue so that if another gem has
  # already set the checked level by the time we
  # get to it, we don't fail outright.
  nil
end

module RubyLsp
  # No-op all inline type assertions defined in T
  module InlineTypeAssertions
    def absurd(value)
      value
    end

    def any(type_a, type_b, *types)
      T::Types::Union.new([type_a, type_b, *types])
    end

    def assert_type!(value, type, checked: true)
      value
    end

    def bind(value, type, checked: true)
      value
    end

    def cast(value, type, checked: true)
      value
    end

    def let(value, type, checked: true)
      value
    end

    def must(arg)
      arg
    end

    def nilable(type)
      T::Types::Union.new([type, T::Utils::Nilable::NIL_TYPE])
    end

    def unsafe(value)
      value
    end

    T.singleton_class.prepend(self)
  end
end
