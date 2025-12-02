# typed: strict
# frozen_string_literal: true

module RubyIndexer
  class Entry
    #: Configuration
    attr_reader :configuration

    #: String
    attr_reader :name

    #: URI::Generic
    attr_reader :uri

    #: RubyIndexer::Location
    attr_reader :location

    alias_method :name_location, :location

    #: Symbol
    attr_accessor :visibility

    #: (Configuration configuration, String name, URI::Generic uri, Location location, String? comments) -> void
    def initialize(configuration, name, uri, location, comments)
      @configuration = configuration
      @name = name
      @uri = uri
      @comments = comments
      @visibility = :public #: Symbol
      @location = location
    end

    #: -> bool
    def public?
      @visibility == :public
    end

    #: -> bool
    def protected?
      @visibility == :protected
    end

    #: -> bool
    def private?
      @visibility == :private
    end

    #: -> String
    def file_name
      if @uri.scheme == "untitled"
        @uri.opaque #: as !nil
      else
        File.basename(
          file_path, #: as !nil
        )
      end
    end

    #: -> String?
    def file_path
      @uri.full_path
    end

    #: -> String
    def comments
      @comments ||= begin
        # Parse only the comments based on the file path, which is much faster than parsing the entire file
        path = file_path
        parsed_comments = path ? Prism.parse_file_comments(path) : []

        # Group comments based on whether they belong to a single block of comments
        grouped = parsed_comments.slice_when do |left, right|
          left.location.start_line + 1 != right.location.start_line
        end

        # Find the group that is either immediately or two lines above the current entry
        correct_group = grouped.find do |group|
          comment_end_line = group.last.location.start_line
          (comment_end_line..comment_end_line + 1).cover?(@location.start_line - 1)
        end

        # If we found something, we join the comments together. Otherwise, the entry has no documentation and we don't
        # want to accidentally re-parse it, so we set it to an empty string. If an entry is updated, the entire entry
        # object is dropped, so this will not prevent updates
        if correct_group
          correct_group.filter_map do |comment|
            content = comment.slice.chomp

            if content.valid_encoding? && !content.match?(@configuration.magic_comment_regex)
              content.delete_prefix!("#")
              content.delete_prefix!(" ")
              content
            end
          end.join("\n")
        else
          ""
        end
      rescue Errno::ENOENT
        # If the file was deleted, but the entry hasn't been removed yet (could happen due to concurrency), then we do
        # not want to fail. Just set the comments to an empty string
        ""
      end
    end

    # @abstract
    class ModuleOperation
      #: String
      attr_reader :module_name

      #: (String module_name) -> void
      def initialize(module_name)
        @module_name = module_name
      end
    end

    class Include < ModuleOperation; end
    class Prepend < ModuleOperation; end

    # @abstract
    class Namespace < Entry
      #: Array[String]
      attr_reader :nesting

      # Returns the location of the constant name, excluding the parent class or the body
      #: Location
      attr_reader :name_location

      #: (Configuration configuration, Array[String] nesting, URI::Generic uri, Location location, Location name_location, String? comments) -> void
      def initialize(configuration, nesting, uri, location, name_location, comments) # rubocop:disable Metrics/ParameterLists
        @name = nesting.join("::") #: String
        # The original nesting where this namespace was discovered
        @nesting = nesting

        super(configuration, @name, uri, location, comments)

        @name_location = name_location
      end

      #: -> Array[String]
      def mixin_operation_module_names
        mixin_operations.map(&:module_name)
      end

      # Stores all explicit prepend, include and extend operations in the exact order they were discovered in the source
      # code. Maintaining the order is essential to linearize ancestors the right way when a module is both included
      # and prepended
      #: -> Array[ModuleOperation]
      def mixin_operations
        @mixin_operations ||= [] #: Array[ModuleOperation]?
      end

      #: -> Integer
      def ancestor_hash
        mixin_operation_module_names.hash
      end
    end

    class Module < Namespace
    end

    class Class < Namespace
      # The unresolved name of the parent class. This may return `nil`, which indicates the lack of an explicit parent
      # and therefore ::Object is the correct parent class
      #: String?
      attr_reader :parent_class

      #: (Configuration configuration, Array[String] nesting, URI::Generic uri, Location location, Location name_location, String? comments, String? parent_class) -> void
      def initialize(configuration, nesting, uri, location, name_location, comments, parent_class) # rubocop:disable Metrics/ParameterLists
        super(configuration, nesting, uri, location, name_location, comments)
        @parent_class = parent_class
      end

      # @override
      #: -> Integer
      def ancestor_hash
        [mixin_operation_module_names, @parent_class].hash
      end
    end

    class SingletonClass < Class
      #: (Location location, Location name_location, String? comments) -> void
      def update_singleton_information(location, name_location, comments)
        @location = location
        @name_location = name_location
        (@comments ||= +"") << comments if comments
      end
    end

    class Constant < Entry
    end

    # @abstract
    class Parameter
      # Name includes just the name of the parameter, excluding symbols like splats
      #: Symbol
      attr_reader :name

      # Decorated name is the parameter name including the splat or block prefix, e.g.: `*foo`, `**foo` or `&block`
      alias_method :decorated_name, :name

      #: (name: Symbol) -> void
      def initialize(name:)
        @name = name
      end
    end

    # A required method parameter, e.g. `def foo(a)`
    class RequiredParameter < Parameter
    end

    # An optional method parameter, e.g. `def foo(a = 123)`
    class OptionalParameter < Parameter
      # @override
      #: -> Symbol
      def decorated_name
        :"#{@name} = <default>"
      end
    end

    # An required keyword method parameter, e.g. `def foo(a:)`
    class KeywordParameter < Parameter
      # @override
      #: -> Symbol
      def decorated_name
        :"#{@name}:"
      end
    end

    # An optional keyword method parameter, e.g. `def foo(a: 123)`
    class OptionalKeywordParameter < Parameter
      # @override
      #: -> Symbol
      def decorated_name
        :"#{@name}: <default>"
      end
    end

    # A rest method parameter, e.g. `def foo(*a)`
    class RestParameter < Parameter
      DEFAULT_NAME = :"<anonymous splat>" #: Symbol

      # @override
      #: -> Symbol
      def decorated_name
        :"*#{@name}"
      end
    end

    # A keyword rest method parameter, e.g. `def foo(**a)`
    class KeywordRestParameter < Parameter
      DEFAULT_NAME = :"<anonymous keyword splat>" #: Symbol

      # @override
      #: -> Symbol
      def decorated_name
        :"**#{@name}"
      end
    end

    # A block method parameter, e.g. `def foo(&block)`
    class BlockParameter < Parameter
      DEFAULT_NAME = :"<anonymous block>" #: Symbol

      class << self
        #: -> BlockParameter
        def anonymous
          new(name: DEFAULT_NAME)
        end
      end

      # @override
      #: -> Symbol
      def decorated_name
        :"&#{@name}"
      end
    end

    # A forwarding method parameter, e.g. `def foo(...)`
    class ForwardingParameter < Parameter
      #: -> void
      def initialize
        # You can't name a forwarding parameter, it's always called `...`
        super(name: :"...")
      end
    end

    # @abstract
    class Member < Entry
      #: Entry::Namespace?
      attr_reader :owner

      #: (Configuration configuration, String name, URI::Generic uri, Location location, String? comments, Symbol visibility, Entry::Namespace? owner) -> void
      def initialize(configuration, name, uri, location, comments, visibility, owner) # rubocop:disable Metrics/ParameterLists
        super(configuration, name, uri, location, comments)
        @visibility = visibility
        @owner = owner
      end

      # @abstract
      #: -> Array[Signature]
      def signatures
        raise AbstractMethodInvokedError
      end

      #: -> String
      def decorated_parameters
        first_signature = signatures.first
        return "()" unless first_signature

        "(#{first_signature.format})"
      end

      #: -> String
      def formatted_signatures
        overloads_count = signatures.size
        case overloads_count
        when 1
          ""
        when 2
          "\n(+1 overload)"
        else
          "\n(+#{overloads_count - 1} overloads)"
        end
      end
    end

    class Accessor < Member
      # @override
      #: -> Array[Signature]
      def signatures
        @signatures ||= begin
          params = []
          params << RequiredParameter.new(name: name.delete_suffix("=").to_sym) if name.end_with?("=")
          [Entry::Signature.new(params)]
        end #: Array[Signature]?
      end
    end

    class Method < Member
      # @override
      #: Array[Signature]
      attr_reader :signatures

      # Returns the location of the method name, excluding parameters or the body
      #: Location
      attr_reader :name_location

      #: (Configuration configuration, String name, URI::Generic uri, Location location, Location name_location, String? comments, Array[Signature] signatures, Symbol visibility, Entry::Namespace? owner) -> void
      def initialize(configuration, name, uri, location, name_location, comments, signatures, visibility, owner) # rubocop:disable Metrics/ParameterLists
        super(configuration, name, uri, location, comments, visibility, owner)
        @signatures = signatures
        @name_location = name_location
      end
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
    class UnresolvedConstantAlias < Entry
      #: String
      attr_reader :target

      #: Array[String]
      attr_reader :nesting

      #: (Configuration configuration, String target, Array[String] nesting, String name, URI::Generic uri, Location location, String? comments) -> void
      def initialize(configuration, target, nesting, name, uri, location, comments) # rubocop:disable Metrics/ParameterLists
        super(configuration, name, uri, location, comments)

        @target = target
        @nesting = nesting
      end
    end

    # Alias represents a resolved alias, which points to an existing constant target
    class ConstantAlias < Entry
      #: String
      attr_reader :target

      #: (String target, UnresolvedConstantAlias unresolved_alias) -> void
      def initialize(target, unresolved_alias)
        super(
          unresolved_alias.configuration,
          unresolved_alias.name,
          unresolved_alias.uri,
          unresolved_alias.location,
          unresolved_alias.comments,
        )

        @visibility = unresolved_alias.visibility
        @target = target
      end
    end

    # Represents a global variable e.g.: $DEBUG
    class GlobalVariable < Entry; end

    # Represents a class variable e.g.: @@a = 1
    class ClassVariable < Entry
      #: Entry::Namespace?
      attr_reader :owner

      #: (Configuration configuration, String name, URI::Generic uri, Location location, String? comments, Entry::Namespace? owner) -> void
      def initialize(configuration, name, uri, location, comments, owner) # rubocop:disable Metrics/ParameterLists
        super(configuration, name, uri, location, comments)
        @owner = owner
      end
    end

    # Represents an instance variable e.g.: @a = 1
    class InstanceVariable < Entry
      #: Entry::Namespace?
      attr_reader :owner

      #: (Configuration configuration, String name, URI::Generic uri, Location location, String? comments, Entry::Namespace? owner) -> void
      def initialize(configuration, name, uri, location, comments, owner) # rubocop:disable Metrics/ParameterLists
        super(configuration, name, uri, location, comments)
        @owner = owner
      end
    end

    # An unresolved method alias is an alias entry for which we aren't sure what the right hand side points to yet. For
    # example, if we have `alias a b`, we create an unresolved alias for `a` because we aren't sure immediate what `b`
    # is referring to
    class UnresolvedMethodAlias < Entry
      #: String
      attr_reader :new_name, :old_name

      #: Entry::Namespace?
      attr_reader :owner

      #: (Configuration configuration, String new_name, String old_name, Entry::Namespace? owner, URI::Generic uri, Location location, String? comments) -> void
      def initialize(configuration, new_name, old_name, owner, uri, location, comments) # rubocop:disable Metrics/ParameterLists
        super(configuration, new_name, uri, location, comments)

        @new_name = new_name
        @old_name = old_name
        @owner = owner
      end
    end

    # A method alias is a resolved alias entry that points to the exact method target it refers to
    class MethodAlias < Entry
      #: (Member | MethodAlias)
      attr_reader :target

      #: Entry::Namespace?
      attr_reader :owner

      #: ((Member | MethodAlias) target, UnresolvedMethodAlias unresolved_alias) -> void
      def initialize(target, unresolved_alias)
        full_comments = +"Alias for #{target.name}\n"
        full_comments << "#{unresolved_alias.comments}\n"
        full_comments << target.comments

        super(
          unresolved_alias.configuration,
          unresolved_alias.new_name,
          unresolved_alias.uri,
          unresolved_alias.location,
          full_comments,
        )

        @target = target
        @owner = unresolved_alias.owner #: Entry::Namespace?
      end

      #: -> String
      def decorated_parameters
        @target.decorated_parameters
      end

      #: -> String
      def formatted_signatures
        @target.formatted_signatures
      end

      #: -> Array[Signature]
      def signatures
        @target.signatures
      end
    end

    # Ruby doesn't support method overloading, so a method will have only one signature.
    # However RBS can represent the concept of method overloading, with different return types based on the arguments
    # passed, so we need to store all the signatures.
    class Signature
      #: Array[Parameter]
      attr_reader :parameters

      #: (Array[Parameter] parameters) -> void
      def initialize(parameters)
        @parameters = parameters
      end

      # Returns a string with the decorated names of the parameters of this member. E.g.: `(a, b = 1, c: 2)`
      #: -> String
      def format
        @parameters.map(&:decorated_name).join(", ")
      end

      # Returns `true` if the given call node arguments array matches this method signature. This method will prefer
      # returning `true` for situations that cannot be analyzed statically, like the presence of splats, keyword splats
      # or forwarding arguments.
      #
      # Since this method is used to detect which overload should be displayed in signature help, it will also return
      # `true` if there are missing arguments since the user may not be done typing yet. For example:
      #
      # ```ruby
      # def foo(a, b); end
      # # All of the following are considered matches because the user might be in the middle of typing and we have to
      # # show them the signature
      # foo
      # foo(1)
      # foo(1, 2)
      # ```
      #: (Array[Prism::Node] arguments) -> bool
      def matches?(arguments)
        min_pos = 0
        max_pos = 0 #: (Integer | Float)
        names = []
        has_forward = false #: bool
        has_keyword_rest = false #: bool

        @parameters.each do |param|
          case param
          when RequiredParameter
            min_pos += 1
            max_pos += 1
          when OptionalParameter
            max_pos += 1
          when RestParameter
            max_pos = Float::INFINITY
          when ForwardingParameter
            max_pos = Float::INFINITY
            has_forward = true
          when KeywordParameter, OptionalKeywordParameter
            names << param.name
          when KeywordRestParameter
            has_keyword_rest = true
          end
        end

        keyword_hash_nodes, positional_args = arguments.partition { |arg| arg.is_a?(Prism::KeywordHashNode) }
        keyword_args = keyword_hash_nodes.first #: as Prism::KeywordHashNode?
          &.elements
        forwarding_arguments, positionals = positional_args.partition do |arg|
          arg.is_a?(Prism::ForwardingArgumentsNode)
        end

        return true if has_forward && min_pos == 0

        # If the only argument passed is a forwarding argument, then anything will match
        (positionals.empty? && forwarding_arguments.any?) ||
          (
            # Check if positional arguments match. This includes required, optional, rest arguments. We also need to
            # verify if there's a trailing forwarding argument, like `def foo(a, ...); end`
            positional_arguments_match?(positionals, forwarding_arguments, keyword_args, min_pos, max_pos) &&
            # If the positional arguments match, we move on to checking keyword, optional keyword and keyword rest
            # arguments. If there's a forward argument, then it will always match. If the method accepts a keyword rest
            # (**kwargs), then we can't analyze statically because the user could be passing a hash and we don't know
            # what the runtime values inside the hash are.
            #
            # If none of those match, then we verify if the user is passing the expect names for the keyword arguments
            (has_forward || has_keyword_rest || keyword_arguments_match?(keyword_args, names))
          )
      end

      #: (Array[Prism::Node] positional_args, Array[Prism::Node] forwarding_arguments, Array[Prism::Node]? keyword_args, Integer min_pos, (Integer | Float) max_pos) -> bool
      def positional_arguments_match?(positional_args, forwarding_arguments, keyword_args, min_pos, max_pos)
        # If the method accepts at least one positional argument and a splat has been passed
        (min_pos > 0 && positional_args.any? { |arg| arg.is_a?(Prism::SplatNode) }) ||
          # If there's at least one positional argument unaccounted for and a keyword splat has been passed
          (min_pos - positional_args.length > 0 && keyword_args&.any? { |arg| arg.is_a?(Prism::AssocSplatNode) }) ||
          # If there's at least one positional argument unaccounted for and a forwarding argument has been passed
          (min_pos - positional_args.length > 0 && forwarding_arguments.any?) ||
          # If the number of positional arguments is within the expected range
          (min_pos > 0 && positional_args.length <= max_pos) ||
          (min_pos == 0 && positional_args.empty?)
      end

      #: (Array[Prism::Node]? args, Array[Symbol] names) -> bool
      def keyword_arguments_match?(args, names)
        return true unless args
        return true if args.any? { |arg| arg.is_a?(Prism::AssocSplatNode) }

        arg_names = args.filter_map do |arg|
          next unless arg.is_a?(Prism::AssocNode)

          key = arg.key
          key.value&.to_sym if key.is_a?(Prism::SymbolNode)
        end

        (arg_names - names).empty?
      end
    end
  end
end
