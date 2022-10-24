# typed: strict
# frozen_string_literal: true

module RubyLsp
  module Requests
    # ![Semantic highlighting demo](../../misc/semantic_highlighting.gif)
    #
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
      include SyntaxTree::WithEnvironment

      TOKEN_TYPES = T.let({
        namespace: 0,
        type: 1,
        class: 2,
        enum: 3,
        interface: 4,
        struct: 5,
        typeParameter: 6,
        parameter: 7,
        variable: 8,
        property: 9,
        enumMember: 10,
        event: 11,
        function: 12,
        method: 13,
        macro: 14,
        keyword: 15,
        modifier: 16,
        comment: 17,
        string: 18,
        number: 19,
        regexp: 20,
        operator: 21,
        decorator: 22,
      }.freeze, T::Hash[Symbol, Integer])

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

      SPECIAL_RUBY_METHODS = T.let([
        Module.instance_methods(false),
        Kernel.instance_methods(false),
        Kernel.methods(false),
        Bundler::Dsl.instance_methods(false),
        Module.private_instance_methods(false),
      ].flatten.map(&:to_s), T::Array[String])

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
        @tree = T.let(T.must(document.tree), SyntaxTree::Node)
        @special_methods = T.let(nil, T.nilable(T::Array[String]))
      end

      sig do
        override.returns(
          T.any(
            LanguageServer::Protocol::Interface::SemanticTokens,
            T.all(T::Array[SemanticToken], Object),
          ),
        )
      end
      def run
        return @tokens unless @document.parsed?

        visit(@tree)
        return @tokens unless @encoder

        @encoder.encode(@tokens)
      end

      sig { override.params(node: SyntaxTree::Call).void }
      def visit_call(node)
        visit(node.receiver)

        message = node.message
        add_token(message.location, :method) if message != :call

        visit(node.arguments)
      end

      sig { override.params(node: SyntaxTree::Command).void }
      def visit_command(node)
        add_token(node.message.location, :method) unless special_method?(node.message.value)
        visit(node.arguments)
      end

      sig { override.params(node: SyntaxTree::CommandCall).void }
      def visit_command_call(node)
        visit(node.receiver)
        add_token(node.message.location, :method)
        visit(node.arguments)
      end

      sig { override.params(node: SyntaxTree::Const).void }
      def visit_const(node)
        add_token(node.location, :namespace)
      end

      sig { override.params(node: SyntaxTree::Def).void }
      def visit_def(node)
        add_token(node.name.location, :method, [:declaration])
        visit(node.params)
        visit(node.bodystmt)
      end

      sig { override.params(node: SyntaxTree::DefEndless).void }
      def visit_def_endless(node)
        add_token(node.name.location, :method, [:declaration])
        visit(node.paren)
        visit(node.operator)
        visit(node.statement)
      end

      sig { override.params(node: SyntaxTree::Defs).void }
      def visit_defs(node)
        visit(node.target)
        visit(node.operator)
        add_token(node.name.location, :method, [:declaration])
        visit(node.params)
        visit(node.bodystmt)
      end

      sig { override.params(node: SyntaxTree::FCall).void }
      def visit_fcall(node)
        add_token(node.value.location, :method) unless special_method?(node.value.value)
        visit(node.arguments)
      end

      sig { override.params(node: SyntaxTree::Kw).void }
      def visit_kw(node)
        case node.value
        when "self"
          add_token(node.location, :variable, [:default_library])
        end
      end

      sig { override.params(node: SyntaxTree::Params).void }
      def visit_params(node)
        node.keywords.each do |keyword,|
          location = keyword.location
          add_token(location_without_colon(location), :parameter)
        end

        node.requireds.each do |required|
          add_token(required.location, :parameter)
        end

        rest = node.keyword_rest
        if rest && !rest.is_a?(SyntaxTree::ArgsForward)
          name = rest.name
          add_token(name.location, :parameter) if name
        end

        super
      end

      sig { override.params(node: SyntaxTree::Field).void }
      def visit_field(node)
        add_token(node.name.location, :method)

        super
      end

      sig { override.params(node: SyntaxTree::VarField).void }
      def visit_var_field(node)
        value = node.value

        case value
        when SyntaxTree::Ident
          type = type_for_local(value)
          add_token(value.location, type)
        else
          visit(value)
        end
      end

      sig { override.params(node: SyntaxTree::VarRef).void }
      def visit_var_ref(node)
        value = node.value

        case value
        when SyntaxTree::Ident
          type = type_for_local(value)
          add_token(value.location, type)
        else
          visit(value)
        end
      end

      sig { override.params(node: SyntaxTree::VCall).void }
      def visit_vcall(node)
        add_token(node.value.location, :method) unless special_method?(node.value.value)
      end

      sig { override.params(node: SyntaxTree::ClassDeclaration).void }
      def visit_class(node)
        add_token(node.constant.location, :class, [:declaration])
        add_token(node.superclass.location, :class) if node.superclass
        visit(node.bodystmt)
      end

      sig { override.params(node: SyntaxTree::ModuleDeclaration).void }
      def visit_module(node)
        add_token(node.constant.location, :class, [:declaration])
        visit(node.bodystmt)
      end

      sig { params(location: SyntaxTree::Location, type: Symbol, modifiers: T::Array[Symbol]).void }
      def add_token(location, type, modifiers = [])
        length = location.end_char - location.start_char
        modifiers_indices = modifiers.filter_map { |modifier| TOKEN_MODIFIERS[modifier] }
        @tokens.push(
          SemanticToken.new(
            location: location,
            length: length,
            type: T.must(TOKEN_TYPES[type]),
            modifier: modifiers_indices,
          ),
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

      sig { params(value: SyntaxTree::Ident).returns(Symbol) }
      def type_for_local(value)
        local = current_environment.find_local(value.value)

        if local.nil? || local.type == :variable
          :variable
        else
          :parameter
        end
      end
    end
  end
end
