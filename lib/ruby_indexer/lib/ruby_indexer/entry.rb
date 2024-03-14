# typed: strict
# frozen_string_literal: true

module RubyIndexer
  class Entry
    extend T::Sig

    sig { returns(String) }
    attr_reader :name

    sig { returns(String) }
    attr_reader :file_path

    sig { returns(Prism::Location) }
    attr_reader :location

    sig { returns(T::Array[String]) }
    attr_reader :comments

    sig { returns(Symbol) }
    attr_accessor :visibility

    sig { params(name: String, file_path: String, location: Prism::Location, comments: T::Array[String]).void }
    def initialize(name, file_path, location, comments)
      @name = name
      @file_path = file_path
      @location = location
      @comments = comments
      @visibility = T.let(:public, Symbol)
    end

    sig { returns(String) }
    def file_name
      File.basename(@file_path)
    end

    class Namespace < Entry
      extend T::Sig
      extend T::Helpers

      abstract!

      sig { returns(T::Array[String]) }
      attr_accessor :included_modules

      sig do
        params(
          name: String,
          file_path: String,
          location: Prism::Location,
          comments: T::Array[String],
        ).void
      end
      def initialize(name, file_path, location, comments)
        super(name, file_path, location, comments)
        @included_modules = T.let([], T::Array[String])
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

      sig do
        params(
          name: String,
          file_path: String,
          location: Prism::Location,
          comments: T::Array[String],
          parent_class: T.nilable(String),
        ).void
      end
      def initialize(name, file_path, location, comments, parent_class)
        super(name, file_path, location, comments)
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
      extend T::Sig
      extend T::Helpers

      abstract!

      sig { returns(T.nilable(Entry::Namespace)) }
      attr_reader :owner

      sig do
        params(
          name: String,
          file_path: String,
          location: Prism::Location,
          comments: T::Array[String],
          owner: T.nilable(Entry::Namespace),
        ).void
      end
      def initialize(name, file_path, location, comments, owner)
        super(name, file_path, location, comments)
        @owner = owner
      end

      sig { abstract.returns(T::Array[Parameter]) }
      def parameters; end
    end

    class Accessor < Member
      extend T::Sig

      sig { override.returns(T::Array[Parameter]) }
      def parameters
        params = []
        params << RequiredParameter.new(name: name.delete_suffix("=").to_sym) if name.end_with?("=")
        params
      end
    end

    class Method < Member
      extend T::Sig
      extend T::Helpers

      abstract!

      sig { override.returns(T::Array[Parameter]) }
      attr_reader :parameters

      sig do
        params(
          name: String,
          file_path: String,
          location: Prism::Location,
          comments: T::Array[String],
          parameters_node: T.nilable(Prism::ParametersNode),
          owner: T.nilable(Entry::Namespace),
        ).void
      end
      def initialize(name, file_path, location, comments, parameters_node, owner) # rubocop:disable Metrics/ParameterLists
        super(name, file_path, location, comments, owner)

        @parameters = T.let(list_params(parameters_node), T::Array[Parameter])
      end

      private

      sig { params(parameters_node: T.nilable(Prism::ParametersNode)).returns(T::Array[Parameter]) }
      def list_params(parameters_node)
        return [] unless parameters_node

        parameters = []

        parameters_node.requireds.each do |required|
          name = parameter_name(required)
          next unless name

          parameters << RequiredParameter.new(name: name)
        end

        parameters_node.optionals.each do |optional|
          name = parameter_name(optional)
          next unless name

          parameters << OptionalParameter.new(name: name)
        end

        parameters_node.keywords.each do |keyword|
          name = parameter_name(keyword)
          next unless name

          case keyword
          when Prism::RequiredKeywordParameterNode
            parameters << KeywordParameter.new(name: name)
          when Prism::OptionalKeywordParameterNode
            parameters << OptionalKeywordParameter.new(name: name)
          end
        end

        rest = parameters_node.rest

        if rest.is_a?(Prism::RestParameterNode)
          rest_name = rest.name || RestParameter::DEFAULT_NAME
          parameters << RestParameter.new(name: rest_name)
        end

        keyword_rest = parameters_node.keyword_rest

        if keyword_rest.is_a?(Prism::KeywordRestParameterNode)
          keyword_rest_name = parameter_name(keyword_rest) || KeywordRestParameter::DEFAULT_NAME
          parameters << KeywordRestParameter.new(name: keyword_rest_name)
        end

        parameters_node.posts.each do |post|
          name = parameter_name(post)
          next unless name

          parameters << RequiredParameter.new(name: name)
        end

        block = parameters_node.block
        parameters << BlockParameter.new(name: block.name || BlockParameter::DEFAULT_NAME) if block

        parameters
      end

      sig { params(node: T.nilable(Prism::Node)).returns(T.nilable(Symbol)) }
      def parameter_name(node)
        case node
        when Prism::RequiredParameterNode, Prism::OptionalParameterNode,
          Prism::RequiredKeywordParameterNode, Prism::OptionalKeywordParameterNode,
          Prism::RestParameterNode, Prism::KeywordRestParameterNode
          node.name
        when Prism::MultiTargetNode
          names = node.lefts.map { |parameter_node| parameter_name(parameter_node) }

          rest = node.rest
          if rest.is_a?(Prism::SplatNode)
            name = rest.expression&.slice
            names << (rest.operator == "*" ? "*#{name}".to_sym : name&.to_sym)
          end

          names << nil if rest.is_a?(Prism::ImplicitRestNode)

          names.concat(node.rights.map { |parameter_node| parameter_name(parameter_node) })

          names_with_commas = names.join(", ")
          :"(#{names_with_commas})"
        end
      end
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
          file_path: String,
          location: Prism::Location,
          comments: T::Array[String],
        ).void
      end
      def initialize(target, nesting, name, file_path, location, comments) # rubocop:disable Metrics/ParameterLists
        super(name, file_path, location, comments)

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
        super(unresolved_alias.name, unresolved_alias.file_path, unresolved_alias.location, unresolved_alias.comments)

        @target = target
      end
    end
  end
end
