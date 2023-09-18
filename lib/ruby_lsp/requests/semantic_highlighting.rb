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

        sig { returns(YARP::Location) }
        attr_reader :location

        sig { returns(Integer) }
        attr_reader :length

        sig { returns(Integer) }
        attr_reader :type

        sig { returns(T::Array[Integer]) }
        attr_reader :modifier

        sig { params(location: YARP::Location, length: Integer, type: Integer, modifier: T::Array[Integer]).void }
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
        @current_scope = T.let(ParameterScope.new, ParameterScope)

        emitter.register(
          self,
          :on_call,
          :on_class,
          :on_def,
          :after_def,
          :on_block,
          :after_block,
          :on_self,
          :on_module,
          :on_local_variable_write,
          :on_local_variable_read,
          :on_block_parameter,
          :on_keyword_parameter,
          :on_keyword_rest_parameter,
          :on_optional_parameter,
          :on_required_parameter,
          :on_rest_parameter,
          :on_constant_read,
          :on_constant_write,
          :on_constant_and_write,
          :on_constant_operator_write,
          :on_constant_or_write,
          :on_constant_target,
          :on_local_variable_and_write,
          :on_local_variable_operator_write,
          :on_local_variable_or_write,
          :on_local_variable_target,
          :on_block_local_variable,
        )
      end

      sig { params(node: YARP::CallNode).void }
      def on_call(node)
        return unless visible?(node, @range)

        message = node.message
        return unless message

        # We can't push a semantic token for [] and []= because the argument inside the brackets is a part of
        # the message_loc
        return if message.start_with?("[") && (message.end_with?("]") || message.end_with?("]="))

        return process_regexp_locals(node) if message == "=~"
        return if special_method?(message)

        type = Support::Sorbet.annotation?(node) ? :type : :method
        add_token(T.must(node.message_loc), type)
      end

      sig { params(node: YARP::ConstantReadNode).void }
      def on_constant_read(node)
        return unless visible?(node, @range)
        # When finding a module or class definition, we will have already pushed a token related to this constant. We
        # need to look at the previous two tokens and if they match this locatione exactly, avoid pushing another token
        # on top of the previous one
        return if @_response.last(2).any? { |token| token.location == node.location }

        add_token(node.location, :namespace)
      end

      sig { params(node: YARP::ConstantWriteNode).void }
      def on_constant_write(node)
        return unless visible?(node, @range)

        add_token(node.name_loc, :namespace)
      end

      sig { params(node: YARP::ConstantAndWriteNode).void }
      def on_constant_and_write(node)
        return unless visible?(node, @range)

        add_token(node.name_loc, :namespace)
      end

      sig { params(node: YARP::ConstantOperatorWriteNode).void }
      def on_constant_operator_write(node)
        return unless visible?(node, @range)

        add_token(node.name_loc, :namespace)
      end

      sig { params(node: YARP::ConstantOrWriteNode).void }
      def on_constant_or_write(node)
        return unless visible?(node, @range)

        add_token(node.name_loc, :namespace)
      end

      sig { params(node: YARP::ConstantTargetNode).void }
      def on_constant_target(node)
        return unless visible?(node, @range)

        add_token(node.location, :namespace)
      end

      sig { params(node: YARP::DefNode).void }
      def on_def(node)
        @current_scope = ParameterScope.new(@current_scope)
        return unless visible?(node, @range)

        add_token(node.name_loc, :method, [:declaration])
      end

      sig { params(node: YARP::DefNode).void }
      def after_def(node)
        @current_scope = T.must(@current_scope.parent)
      end

      sig { params(node: YARP::BlockNode).void }
      def on_block(node)
        @current_scope = ParameterScope.new(@current_scope)
      end

      sig { params(node: YARP::BlockNode).void }
      def after_block(node)
        @current_scope = T.must(@current_scope.parent)
      end

      sig { params(node: YARP::BlockLocalVariableNode).void }
      def on_block_local_variable(node)
        add_token(node.location, :variable)
      end

      sig { params(node: YARP::BlockParameterNode).void }
      def on_block_parameter(node)
        name = node.name
        @current_scope << name.to_sym if name
      end

      sig { params(node: YARP::KeywordParameterNode).void }
      def on_keyword_parameter(node)
        name = node.name
        @current_scope << name.to_s.delete_suffix(":").to_sym if name

        return unless visible?(node, @range)

        location = node.name_loc
        add_token(location.copy(length: location.length - 1), :parameter)
      end

      sig { params(node: YARP::KeywordRestParameterNode).void }
      def on_keyword_rest_parameter(node)
        name = node.name

        if name
          @current_scope << name.to_sym

          add_token(T.must(node.name_loc), :parameter) if visible?(node, @range)
        end
      end

      sig { params(node: YARP::OptionalParameterNode).void }
      def on_optional_parameter(node)
        @current_scope << node.name
        return unless visible?(node, @range)

        add_token(node.name_loc, :parameter)
      end

      sig { params(node: YARP::RequiredParameterNode).void }
      def on_required_parameter(node)
        @current_scope << node.name
        return unless visible?(node, @range)

        add_token(node.location, :parameter)
      end

      sig { params(node: YARP::RestParameterNode).void }
      def on_rest_parameter(node)
        name = node.name

        if name
          @current_scope << name.to_sym

          add_token(T.must(node.name_loc), :parameter) if visible?(node, @range)
        end
      end

      sig { params(node: YARP::SelfNode).void }
      def on_self(node)
        return unless visible?(node, @range)

        add_token(node.location, :variable, [:default_library])
      end

      sig { params(node: YARP::LocalVariableWriteNode).void }
      def on_local_variable_write(node)
        return unless visible?(node, @range)

        add_token(node.name_loc, @current_scope.type_for(node.name))
      end

      sig { params(node: YARP::LocalVariableReadNode).void }
      def on_local_variable_read(node)
        return unless visible?(node, @range)

        # Numbered parameters
        if /_\d+/.match?(node.name)
          add_token(node.location, :parameter)
          return
        end

        add_token(node.location, @current_scope.type_for(node.name))
      end

      sig { params(node: YARP::LocalVariableAndWriteNode).void }
      def on_local_variable_and_write(node)
        return unless visible?(node, @range)

        add_token(node.name_loc, @current_scope.type_for(node.name))
      end

      sig { params(node: YARP::LocalVariableOperatorWriteNode).void }
      def on_local_variable_operator_write(node)
        return unless visible?(node, @range)

        add_token(node.name_loc, @current_scope.type_for(node.name))
      end

      sig { params(node: YARP::LocalVariableOrWriteNode).void }
      def on_local_variable_or_write(node)
        return unless visible?(node, @range)

        add_token(node.name_loc, @current_scope.type_for(node.name))
      end

      sig { params(node: YARP::LocalVariableTargetNode).void }
      def on_local_variable_target(node)
        return unless visible?(node, @range)

        add_token(node.location, @current_scope.type_for(node.name))
      end

      sig { params(node: YARP::ClassNode).void }
      def on_class(node)
        return unless visible?(node, @range)

        add_token(node.constant_path.location, :class, [:declaration])

        superclass = node.superclass
        add_token(superclass.location, :class) if superclass
      end

      sig { params(node: YARP::ModuleNode).void }
      def on_module(node)
        return unless visible?(node, @range)

        add_token(node.constant_path.location, :namespace, [:declaration])
      end

      sig { params(location: YARP::Location, type: Symbol, modifiers: T::Array[Symbol]).void }
      def add_token(location, type, modifiers = [])
        length = location.end_offset - location.start_offset
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

      # Textmate provides highlighting for a subset of these special Ruby-specific methods.  We want to utilize that
      # highlighting, so we avoid making a semantic token for it.
      sig { params(method_name: String).returns(T::Boolean) }
      def special_method?(method_name)
        SPECIAL_RUBY_METHODS.include?(method_name)
      end

      sig { params(node: YARP::CallNode).void }
      def process_regexp_locals(node)
        receiver = node.receiver

        # The regexp needs to be the receiver of =~ for local variable capture
        return unless receiver.is_a?(YARP::RegularExpressionNode)

        content = receiver.content
        loc = receiver.content_loc

        # For each capture name we find in the regexp, look for a local in the current_scope
        Regexp.new(content, Regexp::FIXEDENCODING).names.each do |name|
          # The +3 is to compensate for the "(?<" part of the capture name
          capture_name_offset = T.must(content.index("(?<#{name}>")) + 3
          local_var_loc = loc.copy(start_offset: loc.start_offset + capture_name_offset, length: name.length)

          add_token(local_var_loc, @current_scope.type_for(name))
        end
      end
    end
  end
end
