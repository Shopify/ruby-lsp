# typed: strict
# frozen_string_literal: true

module RubyLsp
  class Scope
    extend T::Sig

    sig { returns(T.nilable(Scope)) }
    attr_reader :parent

    sig { params(parent: T.nilable(Scope)).void }
    def initialize(parent = nil)
      @parent = parent
      @parameters = T.let(Set.new, T::Set[Symbol])
    end

    sig { params(name: T.any(String, Symbol)).void }
    def <<(name)
      @parameters << name.to_sym
    end

    sig { params(name: T.any(Symbol, String)).returns(Symbol) }
    def type_for(name)
      parameter?(name) ? :parameter : :variable
    end

    sig { params(name: T.any(Symbol, String)).returns(T::Boolean) }
    def parameter?(name)
      sym = name.to_sym
      @parameters.include?(sym) || (!@parent.nil? && @parent.parameter?(sym))
    end
  end
end
