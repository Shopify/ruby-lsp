# typed: strict
# frozen_string_literal: true

module RubyLsp
  module Requests
    # The [semantic
    # highlighting](https://microsoft.github.io/language-server-protocol/specification#textDocument_semanticTokens)
    # request informs the editor of the correct token types to provide consistent and accurate highlighting for themes.
    #
    # # Example
    #
    # ```ruby
    # def foo
    #   var = 1 # --> semantic highlighting: local variable
    #   some_invocation # --> semantic highlighting: method invocation
    #   var # --> semantic highlighting: local variable
    # end
    # ```
    class SemanticHighlighting < BaseRequest
      extend T::Sig

      TOKEN_TYPES = T.let([
        :variable,
        :method,
        :namespace,
      ].freeze, T::Array[Symbol])

      TOKEN_MODIFIERS = T.let({
        declaration: 0,
        definition: 1,
        readonly: 2,
        static: 3,
        deprecated: 4,
        abstract: 5,
        async: 6,
        modification: 7,
        documentation: 8,
        default_library: 9,
      }.freeze, T::Hash[Symbol, Integer])

      SPECIAL_RUBY_METHODS = T.let((Module.instance_methods(false) +
        Kernel.methods(false) + Bundler::Dsl.instance_methods(false) +
        Module.private_instance_methods(false))
        .map(&:to_s), T::Array[String])

      class SemanticToken < T::Struct
        const :location, SyntaxTree::Location
        const :length, Integer
        const :type, Integer
        const :modifier, T::Array[Integer]
      end

      sig { params(document: Document, encoder: T.nilable(Support::SemanticTokenEncoder)).void }
      def initialize(document, encoder: nil)
        super(document)

        @encoder = encoder
        @tokens = T.let([], T::Array[SemanticToken])
        @tree = T.let(document.tree, SyntaxTree::Node)
        @special_methods = T.let(nil, T.nilable(T::Array[String]))
      end

      sig do
        override.returns(
          T.any(
            LanguageServer::Protocol::Interface::SemanticTokens,
            T.all(T::Array[SemanticToken], Object),
          )
        )
      end
      def run
        visit(@tree)
        return @tokens unless @encoder

        @encoder.encode(@tokens)
      end

      sig { params(node: SyntaxTree::ARefField).void }
      def visit_a_ref_field(node)
        add_token(node.collection.value.location, :variable)
      end

      sig { params(node: SyntaxTree::Call).void }
      def visit_call(node)
        visit(node.receiver)
        add_token(node.message.location, :method)
        visit(node.arguments)
      end

      sig { params(node: SyntaxTree::Command).void }
      def visit_command(node)
        add_token(node.message.location, :method) unless special_method?(node.message.value)
        visit(node.arguments)
      end

      sig { params(node: SyntaxTree::CommandCall).void }
      def visit_command_call(node)
        visit(node.receiver)
        add_token(node.message.location, :method)
        visit(node.arguments)
      end

      sig { params(node: SyntaxTree::Const).void }
      def visit_const(node)
        add_token(node.location, :namespace)
      end

      sig { params(node: SyntaxTree::Def).void }
      def visit_def(node)
        add_token(node.name.location, :method, [:declaration])
        visit(node.params)
        visit(node.bodystmt)
      end

      sig { params(node: SyntaxTree::DefEndless).void }
      def visit_def_endless(node)
        add_token(node.name.location, :method, [:declaration])
        visit(node.paren)
        visit(node.operator)
        visit(node.statement)
      end

      sig { params(node: SyntaxTree::Defs).void }
      def visit_defs(node)
        visit(node.target)
        visit(node.operator)
        add_token(node.name.location, :method, [:declaration])
        visit(node.params)
        visit(node.bodystmt)
      end

      sig { params(node: SyntaxTree::FCall).void }
      def visit_fcall(node)
        add_token(node.value.location, :method) unless special_method?(node.value.value)
        visit(node.arguments)
      end

      sig { params(node: SyntaxTree::Kw).void }
      def visit_kw(node)
        case node.value
        when "self"
          add_token(node.location, :variable, [:default_library])
        end
      end

      sig { params(node: SyntaxTree::MAssign).void }
      def visit_m_assign(node)
        node.target.parts.each do |var_ref|
          add_token(var_ref.value.location, :variable)
        end
      end

      sig { params(node: SyntaxTree::Params).void }
      def visit_params(node)
        node.keywords.each do |keyword,|
          location = keyword.location
          add_token(location_without_colon(location), :variable)
        end

        add_token(node.keyword_rest.name.location, :variable) if node.keyword_rest
      end

      sig { params(node: SyntaxTree::VarField).void }
      def visit_var_field(node)
        case node.value
        when SyntaxTree::Ident
          add_token(node.value.location, :variable)
        else
          visit(node.value)
        end
      end

      sig { params(node: SyntaxTree::VarRef).void }
      def visit_var_ref(node)
        case node.value
        when SyntaxTree::Ident
          add_token(node.value.location, :variable)
        else
          visit(node.value)
        end
      end

      sig { params(node: SyntaxTree::VCall).void }
      def visit_vcall(node)
        add_token(node.value.location, :method) unless special_method?(node.value.value)
      end

      sig { params(location: SyntaxTree::Location, type: Symbol, modifiers: T::Array[Symbol]).void }
      def add_token(location, type, modifiers = [])
        length = location.end_char - location.start_char
        modifiers_indices = modifiers.filter_map { |modifier| TOKEN_MODIFIERS[modifier] }
        @tokens.push(
          SemanticToken.new(
            location: location,
            length: length,
            type: T.must(TOKEN_TYPES.index(type)),
            modifier: modifiers_indices
          )
        )
      end

      private

      # Exclude the ":" symbol at the end of a location
      # We use it on keyword parameters to be consistent
      # with the rest of the parameters
      sig { params(location: T.untyped).returns(SyntaxTree::Location) }
      def location_without_colon(location)
        SyntaxTree::Location.new(
          start_line: location.start_line,
          start_column: location.start_column,
          start_char: location.start_char,
          end_char: location.end_char - 1,
          end_column: location.end_column - 1,
          end_line: location.end_line,
        )
      end

      # Textmate provides highlighting for a subset
      # of these special Ruby-specific methods.
      # We want to utilize that highlighting, so we
      # avoid making a semantic token for it.
      sig { params(method_name: String).returns(T::Boolean) }
      def special_method?(method_name)
        SPECIAL_RUBY_METHODS.include?(method_name)
      end
    end
  end
end
