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

        sig { returns(Prism::Location) }
        attr_reader :location

        sig { returns(Integer) }
        attr_reader :length

        sig { returns(Integer) }
        attr_reader :type

        sig { returns(T::Array[Integer]) }
        attr_reader :modifier

        sig { params(location: Prism::Location, length: Integer, type: Integer, modifier: T::Array[Integer]).void }
        def initialize(location:, length:, type:, modifier:)
          @location = location
          @length = length
          @type = type
          @modifier = modifier
        end
      end

      sig { override.returns(ResponseType) }
      attr_reader :_response

      sig { params(dispatcher: Prism::Dispatcher, range: T.nilable(T::Range[Integer])).void }
      def initialize(dispatcher, range: nil)
        super(dispatcher)

        @_response = T.let([], ResponseType)
        @range = range
        @special_methods = T.let(nil, T.nilable(T::Array[String]))
        @current_scope = T.let(ParameterScope.new, ParameterScope)
        @inside_regex_capture = T.let(false, T::Boolean)

        dispatcher.register(
          self,
          :on_call_node_enter,
          :on_class_node_enter,
          :on_def_node_enter,
          :on_def_node_leave,
          :on_block_node_enter,
          :on_block_node_leave,
          :on_self_node_enter,
          :on_module_node_enter,
          :on_local_variable_write_node_enter,
          :on_local_variable_read_node_enter,
          :on_block_parameter_node_enter,
          :on_required_keyword_parameter_node_enter,
          :on_optional_keyword_parameter_node_enter,
          :on_keyword_rest_parameter_node_enter,
          :on_optional_parameter_node_enter,
          :on_required_parameter_node_enter,
          :on_rest_parameter_node_enter,
          :on_constant_read_node_enter,
          :on_constant_write_node_enter,
          :on_constant_and_write_node_enter,
          :on_constant_operator_write_node_enter,
          :on_constant_or_write_node_enter,
          :on_constant_target_node_enter,
          :on_local_variable_and_write_node_enter,
          :on_local_variable_operator_write_node_enter,
          :on_local_variable_or_write_node_enter,
          :on_local_variable_target_node_enter,
          :on_block_local_variable_node_enter,
          :on_match_write_node_enter,
          :on_match_write_node_leave,
        )
      end

      sig { params(node: Prism::CallNode).void }
      def on_call_node_enter(node)
        return unless visible?(node, @range)

        message = node.message
        return unless message

        # We can't push a semantic token for [] and []= because the argument inside the brackets is a part of
        # the message_loc
        return if message.start_with?("[") && (message.end_with?("]") || message.end_with?("]="))
        return if message == "=~"
        return if special_method?(message)

        type = Support::Sorbet.annotation?(node) ? :type : :method
        add_token(T.must(node.message_loc), type)
      end

      sig { params(node: Prism::MatchWriteNode).void }
      def on_match_write_node_enter(node)
        call = node.call

        if call.message == "=~"
          @inside_regex_capture = true
          process_regexp_locals(call)
        end
      end

      sig { params(node: Prism::MatchWriteNode).void }
      def on_match_write_node_leave(node)
        @inside_regex_capture = true if node.call.message == "=~"
      end

      sig { params(node: Prism::ConstantReadNode).void }
      def on_constant_read_node_enter(node)
        return unless visible?(node, @range)
        # When finding a module or class definition, we will have already pushed a token related to this constant. We
        # need to look at the previous two tokens and if they match this locatione exactly, avoid pushing another token
        # on top of the previous one
        return if @_response.last(2).any? { |token| token.location == node.location }

        add_token(node.location, :namespace)
      end

      sig { params(node: Prism::ConstantWriteNode).void }
      def on_constant_write_node_enter(node)
        return unless visible?(node, @range)

        add_token(node.name_loc, :namespace)
      end

      sig { params(node: Prism::ConstantAndWriteNode).void }
      def on_constant_and_write_node_enter(node)
        return unless visible?(node, @range)

        add_token(node.name_loc, :namespace)
      end

      sig { params(node: Prism::ConstantOperatorWriteNode).void }
      def on_constant_operator_write_node_enter(node)
        return unless visible?(node, @range)

        add_token(node.name_loc, :namespace)
      end

      sig { params(node: Prism::ConstantOrWriteNode).void }
      def on_constant_or_write_node_enter(node)
        return unless visible?(node, @range)

        add_token(node.name_loc, :namespace)
      end

      sig { params(node: Prism::ConstantTargetNode).void }
      def on_constant_target_node_enter(node)
        return unless visible?(node, @range)

        add_token(node.location, :namespace)
      end

      sig { params(node: Prism::DefNode).void }
      def on_def_node_enter(node)
        @current_scope = ParameterScope.new(@current_scope)
        return unless visible?(node, @range)

        add_token(node.name_loc, :method, [:declaration])
      end

      sig { params(node: Prism::DefNode).void }
      def on_def_node_leave(node)
        @current_scope = T.must(@current_scope.parent)
      end

      sig { params(node: Prism::BlockNode).void }
      def on_block_node_enter(node)
        @current_scope = ParameterScope.new(@current_scope)
      end

      sig { params(node: Prism::BlockNode).void }
      def on_block_node_leave(node)
        @current_scope = T.must(@current_scope.parent)
      end

      sig { params(node: Prism::BlockLocalVariableNode).void }
      def on_block_local_variable_node_enter(node)
        add_token(node.location, :variable)
      end

      sig { params(node: Prism::BlockParameterNode).void }
      def on_block_parameter_node_enter(node)
        name = node.name
        @current_scope << name.to_sym if name
      end

      sig { params(node: Prism::RequiredKeywordParameterNode).void }
      def on_required_keyword_parameter_node_enter(node)
        @current_scope << node.name
        return unless visible?(node, @range)

        location = node.name_loc
        add_token(location.copy(length: location.length - 1), :parameter)
      end

      sig { params(node: Prism::OptionalKeywordParameterNode).void }
      def on_optional_keyword_parameter_node_enter(node)
        @current_scope << node.name
        return unless visible?(node, @range)

        location = node.name_loc
        add_token(location.copy(length: location.length - 1), :parameter)
      end

      sig { params(node: Prism::KeywordRestParameterNode).void }
      def on_keyword_rest_parameter_node_enter(node)
        name = node.name

        if name
          @current_scope << name.to_sym

          add_token(T.must(node.name_loc), :parameter) if visible?(node, @range)
        end
      end

      sig { params(node: Prism::OptionalParameterNode).void }
      def on_optional_parameter_node_enter(node)
        @current_scope << node.name
        return unless visible?(node, @range)

        add_token(node.name_loc, :parameter)
      end

      sig { params(node: Prism::RequiredParameterNode).void }
      def on_required_parameter_node_enter(node)
        @current_scope << node.name
        return unless visible?(node, @range)

        add_token(node.location, :parameter)
      end

      sig { params(node: Prism::RestParameterNode).void }
      def on_rest_parameter_node_enter(node)
        name = node.name

        if name
          @current_scope << name.to_sym

          add_token(T.must(node.name_loc), :parameter) if visible?(node, @range)
        end
      end

      sig { params(node: Prism::SelfNode).void }
      def on_self_node_enter(node)
        return unless visible?(node, @range)

        add_token(node.location, :variable, [:default_library])
      end

      sig { params(node: Prism::LocalVariableWriteNode).void }
      def on_local_variable_write_node_enter(node)
        return unless visible?(node, @range)

        add_token(node.name_loc, @current_scope.type_for(node.name))
      end

      sig { params(node: Prism::LocalVariableReadNode).void }
      def on_local_variable_read_node_enter(node)
        return unless visible?(node, @range)

        # Numbered parameters
        if /_\d+/.match?(node.name)
          add_token(node.location, :parameter)
          return
        end

        add_token(node.location, @current_scope.type_for(node.name))
      end

      sig { params(node: Prism::LocalVariableAndWriteNode).void }
      def on_local_variable_and_write_node_enter(node)
        return unless visible?(node, @range)

        add_token(node.name_loc, @current_scope.type_for(node.name))
      end

      sig { params(node: Prism::LocalVariableOperatorWriteNode).void }
      def on_local_variable_operator_write_node_enter(node)
        return unless visible?(node, @range)

        add_token(node.name_loc, @current_scope.type_for(node.name))
      end

      sig { params(node: Prism::LocalVariableOrWriteNode).void }
      def on_local_variable_or_write_node_enter(node)
        return unless visible?(node, @range)

        add_token(node.name_loc, @current_scope.type_for(node.name))
      end

      sig { params(node: Prism::LocalVariableTargetNode).void }
      def on_local_variable_target_node_enter(node)
        # If we're inside a regex capture, Prism will add LocalVariableTarget nodes for each captured variable.
        # Unfortunately, if the regex contains a backslash, the location will be incorrect and we'll end up highlighting
        # the entire regex as a local variable. We process these captures in process_regexp_locals instead and then
        # prevent pushing local variable target tokens. See https://github.com/ruby/prism/issues/1912
        return if @inside_regex_capture

        return unless visible?(node, @range)

        add_token(node.location, @current_scope.type_for(node.name))
      end

      sig { params(node: Prism::ClassNode).void }
      def on_class_node_enter(node)
        return unless visible?(node, @range)

        add_token(node.constant_path.location, :class, [:declaration])

        superclass = node.superclass
        add_token(superclass.location, :class) if superclass
      end

      sig { params(node: Prism::ModuleNode).void }
      def on_module_node_enter(node)
        return unless visible?(node, @range)

        add_token(node.constant_path.location, :namespace, [:declaration])
      end

      private

      sig { params(location: Prism::Location, type: Symbol, modifiers: T::Array[Symbol]).void }
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

      # Textmate provides highlighting for a subset of these special Ruby-specific methods.  We want to utilize that
      # highlighting, so we avoid making a semantic token for it.
      sig { params(method_name: String).returns(T::Boolean) }
      def special_method?(method_name)
        SPECIAL_RUBY_METHODS.include?(method_name)
      end

      sig { params(node: Prism::CallNode).void }
      def process_regexp_locals(node)
        receiver = node.receiver

        # The regexp needs to be the receiver of =~ for local variable capture
        return unless receiver.is_a?(Prism::RegularExpressionNode)

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
