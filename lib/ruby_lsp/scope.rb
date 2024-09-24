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

      # A hash of name => type
      @locals = T.let({}, T::Hash[Symbol, Local])
    end

    # Add a new local to this scope. The types should only be `:parameter` or `:variable`
    sig { params(name: T.any(String, Symbol), type: Symbol).void }
    def add(name, type)
      @locals[name.to_sym] = Local.new(type)
    end

    sig { params(name: T.any(String, Symbol)).returns(T.nilable(Local)) }
    def lookup(name)
      sym = name.to_sym
      entry = @locals[sym]
      return entry if entry
      return unless @parent

      @parent.lookup(sym)
    end

    class Local
      extend T::Sig

      sig { returns(Symbol) }
      attr_reader :type

      sig { params(type: Symbol).void }
      def initialize(type)
        @type = type
      end
    end
  end
end
