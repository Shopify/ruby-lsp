# typed: strict
# frozen_string_literal: true

module RubyIndexer
  class RBSIndexer
    extend T::Sig

    sig { params(index: Index).void }
    def initialize(index)
      @index = index
    end

    sig { void }
    def index_ruby_core
      loader = RBS::EnvironmentLoader.new
      RBS::Environment.from_loader(loader).resolve_type_names

      loader.each_signature do |source, pathname, _buffer, declarations, _directives|
        process_signature(source, pathname, declarations)
      end
    end

    private

    sig { params(source: T.untyped, pathname: Pathname, declarations: T::Array[RBS::AST::Declarations::Base]).void }
    def process_signature(source, pathname, declarations)
      declarations.each do |declaration|
        process_declaration(declaration, pathname)
      end
    end

    sig { params(declaration: RBS::AST::Declarations::Base, pathname: Pathname).void }
    def process_declaration(declaration, pathname)
      case declaration
      when RBS::AST::Declarations::Class
        handle_class_declaration(declaration, pathname)
      when RBS::AST::Declarations::Module
        handle_module_declaration(declaration, pathname)
      else # rubocop:disable Style/EmptyElse
        # Other kinds not yet handled
      end
    end

    sig { params(declaration: RBS::AST::Declarations::Class, pathname: Pathname).void }
    def handle_class_declaration(declaration, pathname)
      nesting = [declaration.name.name.to_s]
      file_path = pathname.to_s
      location = to_ruby_indexer_location(declaration.location)
      comments = Array(declaration.comment&.string)
      parent_class = declaration.super_class&.name&.name&.to_s
      class_entry = Entry::Class.new(nesting, file_path, location, comments, parent_class)
      add_declaration_mixins_to_entry(declaration, class_entry)
      @index << class_entry
    end

    sig { params(declaration: RBS::AST::Declarations::Module, pathname: Pathname).void }
    def handle_module_declaration(declaration, pathname)
      nesting = [declaration.name.name.to_s]
      file_path = pathname.to_s
      location = to_ruby_indexer_location(declaration.location)
      comments = Array(declaration.comment&.string)
      module_entry = Entry::Module.new(nesting, file_path, location, comments)
      add_declaration_mixins_to_entry(declaration, module_entry)
      @index << module_entry
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
        mixin_operation =
          case mixin
          when RBS::AST::Members::Include
            Entry::Include.new(name)
          when RBS::AST::Members::Extend
            Entry::Extend.new(name)
          when RBS::AST::Members::Prepend
            Entry::Prepend.new(name)
          end
        entry.mixin_operations << mixin_operation if mixin_operation
      end
    end
  end
end
