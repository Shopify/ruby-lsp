# typed: strict
# frozen_string_literal: true

module RubyLsp
  module Requests
    # ![Semantic highlighting demo](../../semantic_highlighting.gif)
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
    class SemanticHighlighting < Listener
      extend T::Sig
      extend T::Generic

      ResponseType = type_member { { fixed: T::Array[SemanticToken] } }

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

      sig { override.returns(ResponseType) }
      attr_reader :_response

      sig do
        params(
          emitter: EventEmitter,
          message_queue: Thread::Queue,
          range: T.nilable(T::Range[Integer]),
        ).void
      end
      def initialize(emitter, message_queue, range: nil)
        super(emitter, message_queue)

        @_response = T.let([], ResponseType)
        @range = range
        @special_methods = T.let(nil, T.nilable(T::Array[String]))

        emitter.register(
          self,
          :after_binary,
          :on_block_var,
          :on_call,
          :on_class,
          :on_command,
          :on_command_call,
          :on_const,
          :on_def,
          :on_field,
          :on_kw,
          :on_lambda_var,
          :on_module,
          :on_params,
          :on_var_field,
          :on_var_ref,
          :on_vcall,
        )
      end

      sig { params(node: SyntaxTree::CallNode).void }
      def on_call(node)
        return unless visible?(node, @range)

        message = node.message
        if !message.is_a?(Symbol) && !special_method?(message.value)
          type = Support::Sorbet.annotation?(node) ? :type : :method
          add_token(message.location, type)
        end
      end

      sig { params(node: SyntaxTree::Command).void }
      def on_command(node)
        return unless visible?(node, @range)

        add_token(node.message.location, :method) unless special_method?(node.message.value)
      end

      sig { params(node: SyntaxTree::CommandCall).void }
      def on_command_call(node)
        return unless visible?(node, @range)

        message = node.message
        add_token(message.location, :method) unless message.is_a?(Symbol)
      end

      sig { params(node: SyntaxTree::Const).void }
      def on_const(node)
        return unless visible?(node, @range)
        # When finding a module or class definition, we will have already pushed a token related to this constant. We
        # need to look at the previous two tokens and if they match this locatione exactly, avoid pushing another token
        # on top of the previous one
        return if @_response.last(2).any? { |token| token.location == node.location }

        add_token(node.location, :namespace)
      end

      sig { params(node: SyntaxTree::DefNode).void }
      def on_def(node)
        return unless visible?(node, @range)

        add_token(node.name.location, :method, [:declaration])
      end

      sig { params(node: SyntaxTree::Kw).void }
      def on_kw(node)
        return unless visible?(node, @range)

        case node.value
        when "self"
          add_token(node.location, :variable, [:default_library])
        end
      end

      sig { params(node: SyntaxTree::Params).void }
      def on_params(node)
        return unless visible?(node, @range)

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
      end

      sig { params(node: SyntaxTree::Field).void }
      def on_field(node)
        return unless visible?(node, @range)

        add_token(node.name.location, :method)
      end

      sig { params(node: SyntaxTree::VarField).void }
      def on_var_field(node)
        return unless visible?(node, @range)

        value = node.value

        case value
        when SyntaxTree::Ident
          type = type_for_local(value)
          add_token(value.location, type)
        end
      end

      sig { params(node: SyntaxTree::VarRef).void }
      def on_var_ref(node)
        return unless visible?(node, @range)

        value = node.value

        case value
        when SyntaxTree::Ident
          type = type_for_local(value)
          add_token(value.location, type)
        end
      end

      # All block locals are variables. E.g.: [].each do |x; block_local|
      sig { params(node: SyntaxTree::BlockVar).void }
      def on_block_var(node)
        node.locals.each { |local| add_token(local.location, :variable) }
      end

      # All lambda locals are variables. E.g.: ->(x; lambda_local) {}
      sig { params(node: SyntaxTree::LambdaVar).void }
      def on_lambda_var(node)
        node.locals.each { |local| add_token(local.location, :variable) }
      end

      sig { params(node: SyntaxTree::VCall).void }
      def on_vcall(node)
        return unless visible?(node, @range)

        # A VCall may exist as a local in the current_scope. This happens when used named capture groups in a regexp
        ident = node.value
        value = ident.value
        local = @emitter.current_scope.find_local(value)
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

      sig { params(node: SyntaxTree::Binary).void }
      def after_binary(node)
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
          local = @emitter.current_scope.find_local(name)
          next unless local

          local.definitions.each { |definition| add_token(definition, :variable) }
        end
      end

      sig { params(node: SyntaxTree::ClassDeclaration).void }
      def on_class(node)
        return unless visible?(node, @range)

        add_token(node.constant.location, :class, [:declaration])

        superclass = node.superclass
        add_token(superclass.location, :class) if superclass
      end

      sig { params(node: SyntaxTree::ModuleDeclaration).void }
      def on_module(node)
        return unless visible?(node, @range)

        add_token(node.constant.location, :namespace, [:declaration])
      end

      sig { params(location: SyntaxTree::Location, type: Symbol, modifiers: T::Array[Symbol]).void }
      def add_token(location, type, modifiers = [])
        length = location.end_char - location.start_char
        modifiers_indices = modifiers.filter_map { |modifier| TOKEN_MODIFIERS[modifier] }
        @_response.push(
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
        local = @emitter.current_scope.find_local(value.value)

        if local.nil? || local.type == :variable
          :variable
        else
          :parameter
        end
      end
    end
  end
end
