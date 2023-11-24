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

      sig { returns(Symbol) }
      attr_reader :name

      sig { params(name: Symbol).void }
      def initialize(name:)
        @name = name
      end
    end

    class RequiredParameter < Parameter
    end

    class Accessor < Entry
      extend T::Sig

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

      sig { returns(T::Array[Parameter]) }
      def parameters
        params = []
        params << RequiredParameter.new(name: name.delete_suffix("=").to_sym) if name.end_with?("=")
        params
      end
    end

    class Method < Entry
      extend T::Sig
      extend T::Helpers
      abstract!

      sig { returns(T::Array[Parameter]) }
      attr_reader :parameters

      sig { returns(T.nilable(Entry::Namespace)) }
      attr_reader :owner

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
        super(name, file_path, location, comments)
        @parameters = T.let(list_params(parameters_node), T::Array[Parameter])
        @owner = owner
      end

      private

      sig { params(parameters_node: T.nilable(Prism::ParametersNode)).returns(T::Array[Parameter]) }
      def list_params(parameters_node)
        return [] unless parameters_node

        parameters_node.requireds.filter_map do |required|
          name = parameter_name(required)
          next unless name

          RequiredParameter.new(name: name)
        end
      end

      sig do
        params(node: Prism::Node).returns(T.nilable(Symbol))
      end
      def parameter_name(node)
        case node
        when Prism::RequiredParameterNode
          node.name
        when Prism::MultiTargetNode
          names = [*node.lefts, *node.rest, *node.rights].map { |parameter_node| parameter_name(parameter_node) }

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
