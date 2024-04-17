# typed: strict
# frozen_string_literal: true

module RubyIndexer
  class Entry
    extend T::Sig

    sig { returns(String) }
    attr_reader :name

    sig { returns(Symbol) }
    attr_accessor :visibility

    sig { returns(T::Array[Declaration]) }
    attr_reader :declarations

    sig { params(name: String).void }
    def initialize(name)
      @name = name
      @visibility = T.let(:public, Symbol)
      @declarations = T.let([], T::Array[Declaration])
    end

    sig { params(declaration: Declaration).void }
    def add_declaration(declaration)
      @declarations << declaration
    end

    sig { returns(T::Array[String]) }
    def comments
      @declarations.flat_map(&:comments)
    end

    # A declaration represents a single place in the code where a declaration for the given entry exists. For example,
    # if a class is re-opened multiple times, there will be a single entry for the class with multiple declarations.
    # This base declaration class can be used to track any general identifiers if the only information they contain is a
    # file path, a location and some comments
    class Declaration
      extend T::Sig

      sig { returns(String) }
      attr_reader :file_path

      sig { returns(RubyIndexer::Location) }
      attr_reader :location

      sig { returns(T::Array[String]) }
      attr_reader :comments

      sig do
        params(
          file_path: String,
          location: T.any(Prism::Location, RubyIndexer::Location),
          comments: T::Array[String],
        ).void
      end
      def initialize(file_path, location, comments)
        @file_path = file_path
        @comments = comments
        @location = T.let(
          if location.is_a?(Prism::Location)
            Location.new(
              location.start_line,
              location.end_line,
              location.start_column,
              location.end_column,
            )
          else
            location
          end,
          RubyIndexer::Location,
        )
      end

      sig { returns(String) }
      def file_name
        File.basename(@file_path)
      end
    end

    class MemberDeclaration < Declaration
      extend T::Sig

      sig { returns(T::Array[Entry::Parameter]) }
      attr_reader :parameters

      sig do
        params(
          parameters: T::Array[Entry::Parameter],
          file_path: String,
          location: T.any(Prism::Location, RubyIndexer::Location),
          comments: T::Array[String],
        ).void
      end
      def initialize(parameters, file_path, location, comments)
        super(file_path, location, comments)

        @parameters = parameters
      end
    end

    class Namespace < Entry
      extend T::Sig
      extend T::Helpers

      abstract!

      sig { returns(T::Array[String]) }
      attr_accessor :included_modules

      sig { returns(T::Array[String]) }
      attr_accessor :prepended_modules

      sig { params(name: String).void }
      def initialize(name)
        super(name)
        @included_modules = T.let([], T::Array[String])
        @prepended_modules = T.let([], T::Array[String])
      end

      sig { returns(String) }
      def short_name
        T.must(@name.split("::").last)
      end
    end

    class Module < Namespace
    end

    class Class < Namespace
      extend T::Sig

      # The unresolved name of the parent class. This may return `nil`, which indicates the lack of an explicit parent
      # and therefore ::Object is the correct parent class
      sig { returns(T.nilable(String)) }
      attr_reader :parent_class

      sig { params(name: String, parent_class: T.nilable(String)).void }
      def initialize(name, parent_class)
        super(name)
        @parent_class = T.let(parent_class, T.nilable(String))
      end
    end

    class Constant < Entry
    end

    class Parameter
      extend T::Helpers
      extend T::Sig

      abstract!

      # Name includes just the name of the parameter, excluding symbols like splats
      sig { returns(Symbol) }
      attr_reader :name

      # Decorated name is the parameter name including the splat or block prefix, e.g.: `*foo`, `**foo` or `&block`
      alias_method :decorated_name, :name

      sig { params(name: Symbol).void }
      def initialize(name:)
        @name = name
      end
    end

    # A required method parameter, e.g. `def foo(a)`
    class RequiredParameter < Parameter
    end

    # An optional method parameter, e.g. `def foo(a = 123)`
    class OptionalParameter < Parameter
    end

    # An required keyword method parameter, e.g. `def foo(a:)`
    class KeywordParameter < Parameter
      sig { override.returns(Symbol) }
      def decorated_name
        :"#{@name}:"
      end
    end

    # An optional keyword method parameter, e.g. `def foo(a: 123)`
    class OptionalKeywordParameter < Parameter
      sig { override.returns(Symbol) }
      def decorated_name
        :"#{@name}:"
      end
    end

    # A rest method parameter, e.g. `def foo(*a)`
    class RestParameter < Parameter
      DEFAULT_NAME = T.let(:"<anonymous splat>", Symbol)

      sig { override.returns(Symbol) }
      def decorated_name
        :"*#{@name}"
      end
    end

    # A keyword rest method parameter, e.g. `def foo(**a)`
    class KeywordRestParameter < Parameter
      DEFAULT_NAME = T.let(:"<anonymous keyword splat>", Symbol)

      sig { override.returns(Symbol) }
      def decorated_name
        :"**#{@name}"
      end
    end

    # A block method parameter, e.g. `def foo(&block)`
    class BlockParameter < Parameter
      DEFAULT_NAME = T.let(:"<anonymous block>", Symbol)

      sig { override.returns(Symbol) }
      def decorated_name
        :"&#{@name}"
      end
    end

    class Member < Entry
      extend T::Helpers
      abstract!

      sig { returns(T.nilable(Entry::Namespace)) }
      attr_reader :owner

      sig { params(name: String, owner: T.nilable(Entry::Namespace)).void }
      def initialize(name, owner)
        super(name)
        @owner = owner
      end
    end

    class Accessor < Member
    end

    class Method < Member
      extend T::Helpers
      abstract!
    end

    class SingletonMethod < Method
    end

    class InstanceMethod < Method
    end

    # An UnresolvedAlias points to a constant alias with a right hand side that has not yet been resolved. For
    # example, if we find
    #
    # ```ruby
    #   CONST = Foo
    # ```
    # Before we have discovered `Foo`, there's no way to eagerly resolve this alias to the correct target constant.
    # All aliases are inserted as UnresolvedAlias in the index first and then we lazily resolve them to the correct
    # target in [rdoc-ref:Index#resolve]. If the right hand side contains a constant that doesn't exist, then it's not
    # possible to resolve the alias and it will remain an UnresolvedAlias until the right hand side constant exists
    class UnresolvedAlias < Entry
      extend T::Sig

      sig { returns(String) }
      attr_reader :target

      sig { returns(T::Array[String]) }
      attr_reader :nesting

      sig do
        params(
          target: String,
          nesting: T::Array[String],
          name: String,
        ).void
      end
      def initialize(target, nesting, name)
        super(name)

        @target = target
        @nesting = nesting
      end
    end

    # Alias represents a resolved alias, which points to an existing constant target
    class Alias < Entry
      extend T::Sig

      sig { returns(String) }
      attr_reader :target

      sig { params(target: String, unresolved_alias: UnresolvedAlias).void }
      def initialize(target, unresolved_alias)
        super(unresolved_alias.name)

        @target = target
        @declarations = unresolved_alias.declarations
      end
    end
  end
end
