# typed: strict
# frozen_string_literal: true

module RubyIndexer
  class Entry
    class Visibility < T::Enum
      enums do
        PUBLIC = new(:public)
        PROTECTED = new(:protected)
        PRIVATE = new(:private)
      end
    end

    extend T::Sig

    sig { returns(String) }
    attr_reader :name

    sig { returns(String) }
    attr_reader :file_path

    sig { returns(RubyIndexer::Location) }
    attr_reader :location

    alias_method :name_location, :location

    sig { returns(Visibility) }
    attr_accessor :visibility

    sig do
      params(
        name: String,
        file_path: String,
        location: T.any(Prism::Location, RubyIndexer::Location),
        comments: T.nilable(String),
        encoding: Encoding,
      ).void
    end
    def initialize(name, file_path, location, comments, encoding)
      @name = name
      @file_path = file_path
      @comments = comments
      @visibility = T.let(Visibility::PUBLIC, Visibility)

      @location = T.let(
        if location.is_a?(Prism::Location)
          Location.new(
            location.start_line,
            location.end_line,
            location.start_code_units_column(encoding),
            location.end_code_units_column(encoding),
          )
        else
          location
        end,
        RubyIndexer::Location,
      )
    end

    sig { returns(T::Boolean) }
    def public?
      visibility == Visibility::PUBLIC
    end

    sig { returns(T::Boolean) }
    def protected?
      visibility == Visibility::PROTECTED
    end

    sig { returns(T::Boolean) }
    def private?
      visibility == Visibility::PRIVATE
    end

    sig { returns(String) }
    def file_name
      File.basename(@file_path)
    end

    sig { returns(String) }
    def comments
      @comments ||= begin
        # Parse only the comments based on the file path, which is much faster than parsing the entire file
        parsed_comments = Prism.parse_file_comments(@file_path)

        # Group comments based on whether they belong to a single block of comments
        grouped = parsed_comments.slice_when do |left, right|
          left.location.start_line + 1 != right.location.start_line
        end

        # Find the group that is either immediately or two lines above the current entry
        correct_group = grouped.find do |group|
          comment_end_line = group.last.location.start_line
          (comment_end_line - 1..comment_end_line).cover?(@location.start_line - 1)
        end

        # If we found something, we join the comments together. Otherwise, the entry has no documentation and we don't
        # want to accidentally re-parse it, so we set it to an empty string. If an entry is updated, the entire entry
        # object is dropped, so this will not prevent updates
        if correct_group
          correct_group.filter_map do |comment|
            content = comment.slice.chomp

            if content.valid_encoding?
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

    class ModuleOperation
      extend T::Sig
      extend T::Helpers

      abstract!

      sig { returns(String) }
      attr_reader :module_name

      sig { params(module_name: String).void }
      def initialize(module_name)
        @module_name = module_name
      end
    end

    class Include < ModuleOperation; end
    class Prepend < ModuleOperation; end

    class Namespace < Entry
      extend T::Sig
      extend T::Helpers

      abstract!

      sig { returns(T::Array[String]) }
      attr_reader :nesting

      # Returns the location of the constant name, excluding the parent class or the body
      sig { returns(Location) }
      attr_reader :name_location

      sig do
        params(
          nesting: T::Array[String],
          file_path: String,
          location: T.any(Prism::Location, RubyIndexer::Location),
          name_location: T.any(Prism::Location, Location),
          comments: T.nilable(String),
          encoding: Encoding,
        ).void
      end
      def initialize(nesting, file_path, location, name_location, comments, encoding) # rubocop:disable Metrics/ParameterLists
        @name = T.let(nesting.join("::"), String)
        # The original nesting where this namespace was discovered
        @nesting = nesting

        super(@name, file_path, location, comments, encoding)

        @name_location = T.let(
          if name_location.is_a?(Prism::Location)
            Location.new(
              name_location.start_line,
              name_location.end_line,
              name_location.start_code_units_column(encoding),
              name_location.end_code_units_column(encoding),
            )
          else
            name_location
          end,
          RubyIndexer::Location,
        )
      end

      sig { returns(T::Array[String]) }
      def mixin_operation_module_names
        mixin_operations.map(&:module_name)
      end

      # Stores all explicit prepend, include and extend operations in the exact order they were discovered in the source
      # code. Maintaining the order is essential to linearize ancestors the right way when a module is both included
      # and prepended
      sig { returns(T::Array[ModuleOperation]) }
      def mixin_operations
        @mixin_operations ||= T.let([], T.nilable(T::Array[ModuleOperation]))
      end

      sig { returns(Integer) }
      def ancestor_hash
        mixin_operation_module_names.hash
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
          nesting: T::Array[String],
          file_path: String,
          location: T.any(Prism::Location, RubyIndexer::Location),
          name_location: T.any(Prism::Location, Location),
          comments: T.nilable(String),
          encoding: Encoding,
          parent_class: T.nilable(String),
        ).void
      end
      def initialize(nesting, file_path, location, name_location, comments, encoding, parent_class) # rubocop:disable Metrics/ParameterLists
        super(nesting, file_path, location, name_location, comments, encoding)
        @parent_class = parent_class
      end

      sig { override.returns(Integer) }
      def ancestor_hash
        [mixin_operation_module_names, @parent_class].hash
      end
    end

    class SingletonClass < Class
      extend T::Sig

      sig do
        params(
          location: Prism::Location,
          name_location: Prism::Location,
          comments: T.nilable(String),
          encoding: Encoding,
        ).void
      end
      def update_singleton_information(location, name_location, comments, encoding)
        # Create a new RubyIndexer::Location object from the Prism location
        @location = Location.new(
          location.start_line,
          location.end_line,
          location.start_code_units_column(encoding),
          location.end_code_units_column(encoding),
        )
        @name_location = Location.new(
          name_location.start_line,
          name_location.end_line,
          name_location.start_code_units_column(encoding),
          name_location.end_code_units_column(encoding),
        )
        (@comments ||= +"") << comments if comments
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
      sig { override.returns(Symbol) }
      def decorated_name
        :"#{@name} = <default>"
      end
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
        :"#{@name}: <default>"
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

      class << self
        extend T::Sig
        sig { returns(BlockParameter) }
        def anonymous
          new(name: DEFAULT_NAME)
        end
      end

      sig { override.returns(Symbol) }
      def decorated_name
        :"&#{@name}"
      end
    end

    # A forwarding method parameter, e.g. `def foo(...)`
    class ForwardingParameter < Parameter
      extend T::Sig

      sig { void }
      def initialize
        # You can't name a forwarding parameter, it's always called `...`
        super(name: :"...")
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
          location: T.any(Prism::Location, RubyIndexer::Location),
          comments: T.nilable(String),
          encoding: Encoding,
          visibility: Visibility,
          owner: T.nilable(Entry::Namespace),
        ).void
      end
      def initialize(name, file_path, location, comments, encoding, visibility, owner) # rubocop:disable Metrics/ParameterLists
        super(name, file_path, location, comments, encoding)
        @visibility = visibility
        @owner = owner
      end

      sig { abstract.returns(T::Array[Entry::Signature]) }
      def signatures; end

      sig { returns(String) }
      def decorated_parameters
        first_signature = signatures.first
        return "()" unless first_signature

        "(#{first_signature.format})"
      end

      sig { returns(String) }
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
      extend T::Sig

      sig { override.returns(T::Array[Signature]) }
      def signatures
        @signatures ||= T.let(
          begin
            params = []
            params << RequiredParameter.new(name: name.delete_suffix("=").to_sym) if name.end_with?("=")
            [Entry::Signature.new(params)]
          end,
          T.nilable(T::Array[Signature]),
        )
      end
    end

    class Method < Member
      extend T::Sig

      sig { override.returns(T::Array[Signature]) }
      attr_reader :signatures

      # Returns the location of the method name, excluding parameters or the body
      sig { returns(Location) }
      attr_reader :name_location

      sig do
        params(
          name: String,
          file_path: String,
          location: T.any(Prism::Location, RubyIndexer::Location),
          name_location: T.any(Prism::Location, Location),
          comments: T.nilable(String),
          encoding: Encoding,
          signatures: T::Array[Signature],
          visibility: Visibility,
          owner: T.nilable(Entry::Namespace),
        ).void
      end
      def initialize(name, file_path, location, name_location, comments, encoding, signatures, visibility, owner) # rubocop:disable Metrics/ParameterLists
        super(name, file_path, location, comments, encoding, visibility, owner)
        @signatures = signatures
        @name_location = T.let(
          if name_location.is_a?(Prism::Location)
            Location.new(
              name_location.start_line,
              name_location.end_line,
              name_location.start_code_units_column(encoding),
              name_location.end_code_units_column(encoding),
            )
          else
            name_location
          end,
          RubyIndexer::Location,
        )
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
          location: T.any(Prism::Location, RubyIndexer::Location),
          comments: T.nilable(String),
          encoding: Encoding,
        ).void
      end
      def initialize(target, nesting, name, file_path, location, comments, encoding) # rubocop:disable Metrics/ParameterLists
        super(name, file_path, location, comments, encoding)

        @target = target
        @nesting = nesting
      end
    end

    # Alias represents a resolved alias, which points to an existing constant target
    class ConstantAlias < Entry
      extend T::Sig

      sig { returns(String) }
      attr_reader :target

      sig { params(target: String, unresolved_alias: UnresolvedConstantAlias, encoding: Encoding).void }
      def initialize(target, unresolved_alias, encoding)
        super(
          unresolved_alias.name,
          unresolved_alias.file_path,
          unresolved_alias.location,
          unresolved_alias.comments,
          encoding
        )

        @visibility = unresolved_alias.visibility
        @target = target
      end
    end

    # Represents a global variable e.g.: $DEBUG
    class GlobalVariable < Entry; end

    # Represents an instance variable e.g.: @a = 1
    class InstanceVariable < Entry
      sig { returns(T.nilable(Entry::Namespace)) }
      attr_reader :owner

      sig do
        params(
          name: String,
          file_path: String,
          location: T.any(Prism::Location, RubyIndexer::Location),
          comments: T.nilable(String),
          encoding: Encoding,
          owner: T.nilable(Entry::Namespace),
        ).void
      end
      def initialize(name, file_path, location, comments, encoding, owner) # rubocop:disable Metrics/ParameterLists
        super(name, file_path, location, comments, encoding)
        @owner = owner
      end
    end

    # An unresolved method alias is an alias entry for which we aren't sure what the right hand side points to yet. For
    # example, if we have `alias a b`, we create an unresolved alias for `a` because we aren't sure immediate what `b`
    # is referring to
    class UnresolvedMethodAlias < Entry
      extend T::Sig

      sig { returns(String) }
      attr_reader :new_name, :old_name

      sig { returns(T.nilable(Entry::Namespace)) }
      attr_reader :owner

      sig do
        params(
          new_name: String,
          old_name: String,
          owner: T.nilable(Entry::Namespace),
          file_path: String,
          location: T.any(Prism::Location, RubyIndexer::Location),
          comments: T.nilable(String),
          encoding: Encoding,
        ).void
      end
      def initialize(new_name, old_name, owner, file_path, location, comments, encoding) # rubocop:disable Metrics/ParameterLists
        super(new_name, file_path, location, comments, encoding)

        @new_name = new_name
        @old_name = old_name
        @owner = owner
      end
    end

    # A method alias is a resolved alias entry that points to the exact method target it refers to
    class MethodAlias < Entry
      extend T::Sig

      sig { returns(T.any(Member, MethodAlias)) }
      attr_reader :target

      sig { returns(T.nilable(Entry::Namespace)) }
      attr_reader :owner

      sig do
        params(target: T.any(Member, MethodAlias), unresolved_alias: UnresolvedMethodAlias, encoding: Encoding).void
      end
      def initialize(target, unresolved_alias, encoding)
        full_comments = +"Alias for #{target.name}\n"
        full_comments << "#{unresolved_alias.comments}\n"
        full_comments << target.comments

        super(
          unresolved_alias.new_name,
          unresolved_alias.file_path,
          unresolved_alias.location,
          full_comments,
          encoding
        )

        @target = target
        @owner = T.let(unresolved_alias.owner, T.nilable(Entry::Namespace))
      end

      sig { returns(String) }
      def decorated_parameters
        @target.decorated_parameters
      end

      sig { returns(String) }
      def formatted_signatures
        @target.formatted_signatures
      end

      sig { returns(T::Array[Signature]) }
      def signatures
        @target.signatures
      end
    end

    # Ruby doesn't support method overloading, so a method will have only one signature.
    # However RBS can represent the concept of method overloading, with different return types based on the arguments
    # passed, so we need to store all the signatures.
    class Signature
      extend T::Sig

      sig { returns(T::Array[Parameter]) }
      attr_reader :parameters

      sig { params(parameters: T::Array[Parameter]).void }
      def initialize(parameters)
        @parameters = parameters
      end

      # Returns a string with the decorated names of the parameters of this member. E.g.: `(a, b = 1, c: 2)`
      sig { returns(String) }
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
      sig { params(arguments: T::Array[Prism::Node]).returns(T::Boolean) }
      def matches?(arguments)
        min_pos = 0
        max_pos = T.let(0, T.any(Integer, Float))
        names = []
        has_forward = T.let(false, T::Boolean)
        has_keyword_rest = T.let(false, T::Boolean)

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
        keyword_args = T.cast(keyword_hash_nodes.first, T.nilable(Prism::KeywordHashNode))&.elements
        forwarding_arguments, positionals = positional_args.partition do |arg|
          arg.is_a?(Prism::ForwardingArgumentsNode)
        end

        return true if has_forward && min_pos == 0

        # If the only argument passed is a forwarding argument, then anything will match
        (positionals.empty? && forwarding_arguments.any?) ||
          (
            # Check if positional arguments match. This includes required, optional, rest arguments. We also need to
            # verify if there's a trailing forwading argument, like `def foo(a, ...); end`
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

      sig do
        params(
          positional_args: T::Array[Prism::Node],
          forwarding_arguments: T::Array[Prism::Node],
          keyword_args: T.nilable(T::Array[Prism::Node]),
          min_pos: Integer,
          max_pos: T.any(Integer, Float),
        ).returns(T::Boolean)
      end
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

      sig { params(args: T.nilable(T::Array[Prism::Node]), names: T::Array[Symbol]).returns(T::Boolean) }
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
