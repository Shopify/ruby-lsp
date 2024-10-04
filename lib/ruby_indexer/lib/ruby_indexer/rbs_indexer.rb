# typed: strict
# frozen_string_literal: true

module RubyIndexer
  class RBSIndexer
    extend T::Sig

    HAS_UNTYPED_FUNCTION = T.let(!!defined?(RBS::Types::UntypedFunction), T::Boolean)

    sig { params(index: Index).void }
    def initialize(index)
      @index = index
    end

    sig { void }
    def index_ruby_core
      loader = RBS::EnvironmentLoader.new
      RBS::Environment.from_loader(loader).resolve_type_names

      loader.each_signature do |_source, pathname, _buffer, declarations, _directives|
        process_signature(pathname, declarations)
      end
    end

    sig do
      params(
        pathname: Pathname,
        declarations: T::Array[RBS::AST::Declarations::Base],
      ).void
    end
    def process_signature(pathname, declarations)
      declarations.each do |declaration|
        process_declaration(declaration, pathname)
      end
    end

    private

    sig { params(declaration: RBS::AST::Declarations::Base, pathname: Pathname).void }
    def process_declaration(declaration, pathname)
      case declaration
      when RBS::AST::Declarations::Class, RBS::AST::Declarations::Module
        handle_class_or_module_declaration(declaration, pathname)
      when RBS::AST::Declarations::Constant
        namespace_nesting = declaration.name.namespace.path.map(&:to_s)
        handle_constant(declaration, namespace_nesting, pathname.to_s)
      when RBS::AST::Declarations::Global
        handle_global_variable(declaration, pathname)
      else # rubocop:disable Style/EmptyElse
        # Other kinds not yet handled
      end
    end

    sig do
      params(declaration: T.any(RBS::AST::Declarations::Class, RBS::AST::Declarations::Module), pathname: Pathname).void
    end
    def handle_class_or_module_declaration(declaration, pathname)
      nesting = [declaration.name.name.to_s]
      file_path = pathname.to_s
      location = to_ruby_indexer_location(declaration.location)
      comments = comments_to_string(declaration)
      entry = if declaration.is_a?(RBS::AST::Declarations::Class)
        parent_class = declaration.super_class&.name&.name&.to_s
        Entry::Class.new(nesting, file_path, location, location, comments, @index.configuration.encoding, parent_class)
      else
        Entry::Module.new(nesting, file_path, location, location, comments, @index.configuration.encoding)
      end
      add_declaration_mixins_to_entry(declaration, entry)
      @index.add(entry)
      declaration.members.each do |member|
        case member
        when RBS::AST::Members::MethodDefinition
          handle_method(member, entry)
        when RBS::AST::Declarations::Constant
          handle_constant(member, nesting, file_path)
        when RBS::AST::Members::Alias
          # In RBS, an alias means that two methods have the same signature.
          # It does not mean the same thing as a Ruby alias.
          handle_signature_alias(member, entry)
        end
      end
    end

    sig { params(rbs_location: RBS::Location).returns(RubyIndexer::Location) }
    def to_ruby_indexer_location(rbs_location)
      RubyIndexer::Location.new(
        rbs_location.start_line,
        rbs_location.end_line,
        rbs_location.start_column,
        rbs_location.end_column,
      )
    end

    sig do
      params(
        declaration: T.any(RBS::AST::Declarations::Class, RBS::AST::Declarations::Module),
        entry: Entry::Namespace,
      ).void
    end
    def add_declaration_mixins_to_entry(declaration, entry)
      declaration.each_mixin do |mixin|
        name = mixin.name.name.to_s
        case mixin
        when RBS::AST::Members::Include
          entry.mixin_operations << Entry::Include.new(name)
        when RBS::AST::Members::Prepend
          entry.mixin_operations << Entry::Prepend.new(name)
        when RBS::AST::Members::Extend
          singleton = @index.existing_or_new_singleton_class(entry.name)
          singleton.mixin_operations << Entry::Include.new(name)
        end
      end
    end

    sig { params(member: RBS::AST::Members::MethodDefinition, owner: Entry::Namespace).void }
    def handle_method(member, owner)
      name = member.name.name
      file_path = member.location.buffer.name
      location = to_ruby_indexer_location(member.location)
      comments = comments_to_string(member)

      visibility = case member.visibility
      when :private
        Entry::Visibility::PRIVATE
      when :protected
        Entry::Visibility::PROTECTED
      else
        Entry::Visibility::PUBLIC
      end

      real_owner = member.singleton? ? @index.existing_or_new_singleton_class(owner.name) : owner
      signatures = signatures(member)
      @index.add(Entry::Method.new(
        name,
        file_path,
        location,
        location,
        comments,
        @index.configuration.encoding,
        signatures,
        visibility,
        real_owner,
      ))
    end

    sig { params(member: RBS::AST::Members::MethodDefinition).returns(T::Array[Entry::Signature]) }
    def signatures(member)
      member.overloads.map do |overload|
        parameters = process_overload(overload)
        Entry::Signature.new(parameters)
      end
    end

    sig { params(overload: RBS::AST::Members::MethodDefinition::Overload).returns(T::Array[Entry::Parameter]) }
    def process_overload(overload)
      function = overload.method_type.type

      if function.is_a?(RBS::Types::Function)
        parameters = parse_arguments(function)

        block = overload.method_type.block
        parameters << Entry::BlockParameter.anonymous if block&.required
        return parameters
      end

      # Untyped functions are a new RBS feature (since v3.6.0) to declare methods that accept any parameters. For our
      # purposes, accepting any argument is equivalent to `...`
      if HAS_UNTYPED_FUNCTION && function.is_a?(RBS::Types::UntypedFunction)
        [Entry::ForwardingParameter.new]
      else
        []
      end
    end

    sig { params(function: RBS::Types::Function).returns(T::Array[Entry::Parameter]) }
    def parse_arguments(function)
      parameters = []
      parameters.concat(process_required_and_optional_positionals(function))
      parameters.concat(process_trailing_positionals(function)) if function.trailing_positionals
      parameters << process_rest_positionals(function) if function.rest_positionals
      parameters.concat(process_required_keywords(function)) if function.required_keywords
      parameters.concat(process_optional_keywords(function)) if function.optional_keywords
      parameters << process_rest_keywords(function) if function.rest_keywords
      parameters
    end

    sig { params(function: RBS::Types::Function).returns(T::Array[Entry::RequiredParameter]) }
    def process_required_and_optional_positionals(function)
      argument_offset = 0

      required = function.required_positionals.map.with_index(argument_offset) do |param, i|
        # Some parameters don't have names, e.g.
        #   def self.try_convert: [U] (untyped) -> ::Array[U]?
        name = param.name || :"arg#{i}"
        argument_offset += 1

        Entry::RequiredParameter.new(name: name)
      end

      optional = function.optional_positionals.map.with_index(argument_offset) do |param, i|
        # Optional positionals may be unnamed, e.g.
        #  def self.polar: (Numeric, ?Numeric) -> Complex
        name = param.name || :"arg#{i}"

        Entry::OptionalParameter.new(name: name)
      end

      required + optional
    end

    sig { params(function: RBS::Types::Function).returns(T::Array[Entry::OptionalParameter]) }
    def process_trailing_positionals(function)
      function.trailing_positionals.map do |param|
        Entry::OptionalParameter.new(name: param.name)
      end
    end

    sig { params(function: RBS::Types::Function).returns(Entry::RestParameter) }
    def process_rest_positionals(function)
      rest = function.rest_positionals

      rest_name = rest.name || Entry::RestParameter::DEFAULT_NAME

      Entry::RestParameter.new(name: rest_name)
    end

    sig { params(function: RBS::Types::Function).returns(T::Array[Entry::KeywordParameter]) }
    def process_required_keywords(function)
      function.required_keywords.map do |name, _param|
        Entry::KeywordParameter.new(name: name)
      end
    end

    sig { params(function: RBS::Types::Function).returns(T::Array[Entry::OptionalKeywordParameter]) }
    def process_optional_keywords(function)
      function.optional_keywords.map do |name, _param|
        Entry::OptionalKeywordParameter.new(name: name)
      end
    end

    sig { params(function: RBS::Types::Function).returns(Entry::KeywordRestParameter) }
    def process_rest_keywords(function)
      param = function.rest_keywords

      name = param.name || Entry::KeywordRestParameter::DEFAULT_NAME

      Entry::KeywordRestParameter.new(name: name)
    end

    # RBS treats constant definitions differently depend on where they are defined.
    # When constants' rbs are defined inside a class/module block, they are treated as
    # members of the class/module.
    #
    # module Encoding
    #   US_ASCII = ... # US_ASCII is a member of Encoding
    # end
    #
    # When constants' rbs are defined outside a class/module block, they are treated as
    # top-level constants.
    #
    # Complex::I = ... # Complex::I is a top-level constant
    #
    # And we need to handle their nesting differently.
    sig { params(declaration: RBS::AST::Declarations::Constant, nesting: T::Array[String], file_path: String).void }
    def handle_constant(declaration, nesting, file_path)
      fully_qualified_name = [*nesting, declaration.name.name.to_s].join("::")
      @index.add(Entry::Constant.new(
        fully_qualified_name,
        file_path,
        to_ruby_indexer_location(declaration.location),
        comments_to_string(declaration),
        @index.configuration.encoding,
      ))
    end

    sig { params(declaration: RBS::AST::Declarations::Global, pathname: Pathname).void }
    def handle_global_variable(declaration, pathname)
      name = declaration.name.to_s
      file_path = pathname.to_s
      location = to_ruby_indexer_location(declaration.location)
      comments = comments_to_string(declaration)
      encoding = @index.configuration.encoding

      @index.add(Entry::GlobalVariable.new(
        name,
        file_path,
        location,
        comments,
        encoding,
      ))
    end

    sig { params(member: RBS::AST::Members::Alias, owner_entry: Entry::Namespace).void }
    def handle_signature_alias(member, owner_entry)
      file_path = member.location.buffer.name
      comments = comments_to_string(member)

      entry = Entry::UnresolvedMethodAlias.new(
        member.new_name.to_s,
        member.old_name.to_s,
        owner_entry,
        file_path,
        to_ruby_indexer_location(member.location),
        comments,
        @index.configuration.encoding,
      )

      @index.add(entry)
    end

    sig do
      params(declaration: T.any(
        RBS::AST::Declarations::Class,
        RBS::AST::Declarations::Module,
        RBS::AST::Declarations::Constant,
        RBS::AST::Declarations::Global,
        RBS::AST::Members::MethodDefinition,
        RBS::AST::Members::Alias,
      )).returns(T.nilable(String))
    end
    def comments_to_string(declaration)
      declaration.comment&.string
    end
  end
end
