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
      include SyntaxTree::WithScope

      TOKEN_TYPES = T.let(
        {
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
        }.freeze,
        T::Hash[Symbol, Integer],
      )

      TOKEN_MODIFIERS = T.let(
        {
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
        }.freeze,
        T::Hash[Symbol, Integer],
      )

      SPECIAL_RUBY_METHODS = T.let(
        [
          Module.instance_methods(false),
          Kernel.instance_methods(false),
          Kernel.methods(false),
          Bundler::Dsl.instance_methods(false),
          Module.private_instance_methods(false),
        ].flatten.map(&:to_s),
        T::Array[String],
      )

      class SemanticToken
        extend T::Sig

        sig { returns(SyntaxTree::Location) }
        attr_reader :location

        sig { returns(Integer) }
        attr_reader :length

        sig { returns(Integer) }
        attr_reader :type

        sig { returns(T::Array[Integer]) }
        attr_reader :modifier

        sig { params(location: SyntaxTree::Location, length: Integer, type: Integer, modifier: T::Array[Integer]).void }
        def initialize(location:, length:, type:, modifier:)
          @location = location
          @length = length
          @type = type
          @modifier = modifier
        end
      end

      sig do
        params(
          document: Document,
          range: T.nilable(T::Range[Integer]),
          encoder: T.nilable(Support::SemanticTokenEncoder),
        ).void
      end
      def initialize(document, range: nil, encoder: nil)
        super(document)

        @encoder = encoder
        @tokens = T.let([], T::Array[SemanticToken])
        @tree = T.let(T.must(document.tree), SyntaxTree::Node)
        @range = range
        @special_methods = T.let(nil, T.nilable(T::Array[String]))
      end

      sig do
        override.returns(
          T.any(
            Interface::SemanticTokens,
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

      sig { override.params(node: SyntaxTree::CallNode).void }
      def visit_call(node)
        return super unless visible?(node, @range)

        visit(node.receiver)

        message = node.message
        if !message.is_a?(Symbol) && !special_method?(message.value)
          type = Support::Sorbet.annotation?(node) ? :type : :method

          add_token(message.location, type)
        end

        visit(node.arguments)
      end

      sig { override.params(node: SyntaxTree::Command).void }
      def visit_command(node)
        return super unless visible?(node, @range)

        unless special_method?(node.message.value)
          add_token(node.message.location, :method)
        end
        visit(node.arguments)
        visit(node.block)
      end

      sig { override.params(node: SyntaxTree::CommandCall).void }
      def visit_command_call(node)
        return super unless visible?(node, @range)

        visit(node.receiver)
        message = node.message
        add_token(message.location, :method) unless message.is_a?(Symbol)
        visit(node.arguments)
        visit(node.block)
      end

      sig { override.params(node: SyntaxTree::Const).void }
      def visit_const(node)
        return super unless visible?(node, @range)

        add_token(node.location, :namespace)
      end

      sig { override.params(node: SyntaxTree::DefNode).void }
      def visit_def(node)
        return super unless visible?(node, @range)

        add_token(node.name.location, :method, [:declaration])
        visit(node.params)
        visit(node.bodystmt)
        visit(node.target) if node.target
        visit(node.operator) if node.operator
      end

      sig { override.params(node: SyntaxTree::Kw).void }
      def visit_kw(node)
        return super unless visible?(node, @range)

        case node.value
        when "self"
          add_token(node.location, :variable, [:default_library])
        end
      end

      sig { override.params(node: SyntaxTree::Params).void }
      def visit_params(node)
        return super unless visible?(node, @range)

        node.keywords.each do |keyword, *|
          location = keyword.location
          add_token(location_without_colon(location), :parameter)
        end

        node.requireds.each do |required|
          add_token(required.location, :parameter)
        end

        rest = node.keyword_rest
        if rest && !rest.is_a?(SyntaxTree::ArgsForward) && !rest.is_a?(Symbol)
          name = rest.name
          add_token(name.location, :parameter) if name
        end

        super
      end

      sig { override.params(node: SyntaxTree::Field).void }
      def visit_field(node)
        return super unless visible?(node, @range)

        add_token(node.name.location, :method)

        super
      end

      sig { override.params(node: SyntaxTree::VarField).void }
      def visit_var_field(node)
        return super unless visible?(node, @range)

        value = node.value

        case value
        when SyntaxTree::Ident
          type = type_for_local(value)
          add_token(value.location, type)
        when Symbol
          # do nothing
        else
          visit(value)
        end

        super
      end

      sig { override.params(node: SyntaxTree::VarRef).void }
      def visit_var_ref(node)
        return super unless visible?(node, @range)

        value = node.value

        case value
        when SyntaxTree::Ident
          type = type_for_local(value)
          add_token(value.location, type)
        when Symbol
          # do nothing
        else
          visit(value)
        end
      end

      # All block locals are variables. E.g.: [].each do |x; block_local|
      sig { override.params(node: SyntaxTree::BlockVar).void }
      def visit_block_var(node)
        node.locals.each { |local| add_token(local.location, :variable) }
        super
      end

      # All lambda locals are variables. E.g.: ->(x; lambda_local) {}
      sig { override.params(node: SyntaxTree::LambdaVar).void }
      def visit_lambda_var(node)
        node.locals.each { |local| add_token(local.location, :variable) }
        super
      end

      sig { override.params(node: SyntaxTree::VCall).void }
      def visit_vcall(node)
        return super unless visible?(node, @range)

        # A VCall may exist as a local in the current_scope. This happens when used named capture groups in a regexp
        ident = node.value
        value = ident.value
        local = current_scope.find_local(value)
        return if local.nil? && special_method?(value)

        type = if local
          :variable
        elsif Support::Sorbet.annotation?(node)
          :type
        else
          :method
        end

        add_token(node.value.location, type)
      end

      sig { override.params(node: SyntaxTree::Binary).void }
      def visit_binary(node)
        # It's important to visit the regexp first in the WithScope module
        super

        # You can only capture local variables with regexp by using the =~ operator
        return unless node.operator == :=~

        left = node.left
        # The regexp needs to be on the left hand side of the =~ for local variable capture
        return unless left.is_a?(SyntaxTree::RegexpLiteral)

        parts = left.parts
        return unless parts.one?

        content = parts.first
        return unless content.is_a?(SyntaxTree::TStringContent)

        # For each capture name we find in the regexp, look for a local in the current_scope
        Regexp.new(content.value, Regexp::FIXEDENCODING).names.each do |name|
          local = current_scope.find_local(name)
          next unless local

          local.definitions.each { |definition| add_token(definition, :variable) }
        end
      end

      sig { override.params(node: SyntaxTree::ClassDeclaration).void }
      def visit_class(node)
        return super unless visible?(node, @range)

        add_token(node.constant.location, :class, [:declaration])

        superclass = node.superclass
        add_token(superclass.location, :class) if superclass

        visit(node.bodystmt)
      end

      sig { override.params(node: SyntaxTree::ModuleDeclaration).void }
      def visit_module(node)
        return super unless visible?(node, @range)

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
        local = current_scope.find_local(value.value)

        if local.nil? || local.type == :variable
          :variable
        else
          :parameter
        end
      end
    end
  end
end
