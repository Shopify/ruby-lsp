# typed: strict
# frozen_string_literal: true

module RubyLsp
  class Scope
    #: Scope?
    attr_reader :parent

    #: (?Scope? parent) -> void
    def initialize(parent = nil)
      @parent = parent

      # A hash of name => type
      @locals = {} #: Hash[Symbol, Local]
    end

    # Add a new local to this scope. The types should only be `:parameter` or `:variable`
    #: ((String | Symbol) name, Symbol type) -> void
    def add(name, type)
      @locals[name.to_sym] = Local.new(type)
    end

    #: ((String | Symbol) name) -> Local?
    def lookup(name)
      sym = name.to_sym
      entry = @locals[sym]
      return entry if entry
      return unless @parent

      @parent.lookup(sym)
    end

    class Local
      #: Symbol
      attr_reader :type

      #: (Symbol type) -> void
      def initialize(type)
        @type = type
      end
    end
  end
end
