# typed: strict
# frozen_string_literal: true

module RubyIndexer
  class RBSIndexer
    HAS_UNTYPED_FUNCTION = !!defined?(RBS::Types::UntypedFunction) #: bool

    #: (Index index) -> void
    def initialize(index)
      @index = index
    end

    #: -> void
    def index_ruby_core
      loader = RBS::EnvironmentLoader.new
      RBS::Environment.from_loader(loader).resolve_type_names

      loader.each_signature do |_source, pathname, _buffer, declarations, _directives|
        process_signature(pathname, declarations)
      end
    end

    #: (Pathname pathname, Array[RBS::AST::Declarations::Base] declarations) -> void
    def process_signature(pathname, declarations)
      declarations.each do |declaration|
        process_declaration(declaration, pathname)
      end
    end

    private

    #: (RBS::AST::Declarations::Base declaration, Pathname pathname) -> void
    def process_declaration(declaration, pathname)
      case declaration
      when RBS::AST::Declarations::Class, RBS::AST::Declarations::Module
        handle_class_or_module_declaration(declaration, pathname)
      when RBS::AST::Declarations::Constant
        namespace_nesting = declaration.name.namespace.path.map(&:to_s)
        handle_constant(declaration, namespace_nesting, URI::Generic.from_path(path: pathname.to_s))
      when RBS::AST::Declarations::Global
        handle_global_variable(declaration, pathname)
      else # rubocop:disable Style/EmptyElse
        # Other kinds not yet handled
      end
    end

    #: ((RBS::AST::Declarations::Class | RBS::AST::Declarations::Module) declaration, Pathname pathname) -> void
    def handle_class_or_module_declaration(declaration, pathname)
      nesting = [declaration.name.name.to_s]
      uri = URI::Generic.from_path(path: pathname.to_s)
      location = to_ruby_indexer_location(declaration.location)
      comments = comments_to_string(declaration)
      entry = if declaration.is_a?(RBS::AST::Declarations::Class)
        parent_class = declaration.super_class&.name&.name&.to_s
        Entry::Class.new(nesting, uri, location, location, comments, parent_class)
      else
        Entry::Module.new(nesting, uri, location, location, comments)
      end

      add_declaration_mixins_to_entry(declaration, entry)
      @index.add(entry)

      declaration.members.each do |member|
        case member
        when RBS::AST::Members::MethodDefinition
          handle_method(member, entry)
        when RBS::AST::Declarations::Constant
          handle_constant(member, nesting, uri)
        when RBS::AST::Members::Alias
          # In RBS, an alias means that two methods have the same signature.
          # It does not mean the same thing as a Ruby alias.
          handle_signature_alias(member, entry)
        end
      end
    end

    #: (RBS::Location rbs_location) -> RubyIndexer::Location
    def to_ruby_indexer_location(rbs_location)
      RubyIndexer::Location.new(
        rbs_location.start_line,
        rbs_location.end_line,
        rbs_location.start_column,
        rbs_location.end_column,
      )
    end

    #: ((RBS::AST::Declarations::Class | RBS::AST::Declarations::Module) declaration, Entry::Namespace entry) -> void
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

    #: (RBS::AST::Members::MethodDefinition member, Entry::Namespace owner) -> void
    def handle_method(member, owner)
      name = member.name.name
      uri = URI::Generic.from_path(path: member.location.buffer.name)
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
        uri,
        location,
        location,
        comments,
        signatures,
        visibility,
        real_owner,
      ))
    end

    #: (RBS::AST::Members::MethodDefinition member) -> Array[Entry::Signature]
    def signatures(member)
      member.overloads.map do |overload|
        parameters = process_overload(overload)
        Entry::Signature.new(parameters)
      end
    end

    #: (RBS::AST::Members::MethodDefinition::Overload overload) -> Array[Entry::Parameter]
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

    #: (RBS::Types::Function function) -> Array[Entry::Parameter]
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

    #: (RBS::Types::Function function) -> Array[Entry::RequiredParameter]
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

    #: (RBS::Types::Function function) -> Array[Entry::OptionalParameter]
    def process_trailing_positionals(function)
      function.trailing_positionals.map do |param|
        Entry::OptionalParameter.new(name: param.name)
      end
    end

    #: (RBS::Types::Function function) -> Entry::RestParameter
    def process_rest_positionals(function)
      rest = function.rest_positionals

      rest_name = rest.name || Entry::RestParameter::DEFAULT_NAME

      Entry::RestParameter.new(name: rest_name)
    end

    #: (RBS::Types::Function function) -> Array[Entry::KeywordParameter]
    def process_required_keywords(function)
      function.required_keywords.map do |name, _param|
        Entry::KeywordParameter.new(name: name)
      end
    end

    #: (RBS::Types::Function function) -> Array[Entry::OptionalKeywordParameter]
    def process_optional_keywords(function)
      function.optional_keywords.map do |name, _param|
        Entry::OptionalKeywordParameter.new(name: name)
      end
    end

    #: (RBS::Types::Function function) -> Entry::KeywordRestParameter
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
    #: (RBS::AST::Declarations::Constant declaration, Array[String] nesting, URI::Generic uri) -> void
    def handle_constant(declaration, nesting, uri)
      fully_qualified_name = [*nesting, declaration.name.name.to_s].join("::")
      @index.add(Entry::Constant.new(
        fully_qualified_name,
        uri,
        to_ruby_indexer_location(declaration.location),
        comments_to_string(declaration),
      ))
    end

    #: (RBS::AST::Declarations::Global declaration, Pathname pathname) -> void
    def handle_global_variable(declaration, pathname)
      name = declaration.name.to_s
      uri = URI::Generic.from_path(path: pathname.to_s)
      location = to_ruby_indexer_location(declaration.location)
      comments = comments_to_string(declaration)

      @index.add(Entry::GlobalVariable.new(
        name,
        uri,
        location,
        comments,
      ))
    end

    #: (RBS::AST::Members::Alias member, Entry::Namespace owner_entry) -> void
    def handle_signature_alias(member, owner_entry)
      uri = URI::Generic.from_path(path: member.location.buffer.name)
      comments = comments_to_string(member)

      entry = Entry::UnresolvedMethodAlias.new(
        member.new_name.to_s,
        member.old_name.to_s,
        owner_entry,
        uri,
        to_ruby_indexer_location(member.location),
        comments,
      )

      @index.add(entry)
    end

    #: ((RBS::AST::Declarations::Class | RBS::AST::Declarations::Module | RBS::AST::Declarations::Constant | RBS::AST::Declarations::Global | RBS::AST::Members::MethodDefinition | RBS::AST::Members::Alias) declaration) -> String?
    def comments_to_string(declaration)
      declaration.comment&.string
    end
  end
end
