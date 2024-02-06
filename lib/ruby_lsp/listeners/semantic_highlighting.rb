# typed: strict
# frozen_string_literal: true

module RubyLsp
  module Listeners
    class SemanticHighlighting
      include Requests::Support::Common
      extend T::Sig

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

      sig do
        params(
          dispatcher: Prism::Dispatcher,
          response_builder: ResponseBuilders::SemanticHighlighting,
          range: T.nilable(T::Range[Integer]),
        ).void
      end
      def initialize(dispatcher, response_builder, range: nil)
        @response_builder = response_builder
        @range = range
        @special_methods = T.let(nil, T.nilable(T::Array[String]))
        @current_scope = T.let(ParameterScope.new, ParameterScope)
        @inside_regex_capture = T.let(false, T::Boolean)
        @inside_implicit_node = T.let(false, T::Boolean)

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
          :on_implicit_node_enter,
          :on_implicit_node_leave,
        )
      end

      sig { params(node: Prism::CallNode).void }
      def on_call_node_enter(node)
        return if @inside_implicit_node
        return unless visible?(node, @range)

        message = node.message
        return unless message

        # We can't push a semantic token for [] and []= because the argument inside the brackets is a part of
        # the message_loc
        return if message.start_with?("[") && (message.end_with?("]") || message.end_with?("]="))
        return if message == "=~"
        return if special_method?(message)

        type = Requests::Support::Sorbet.annotation?(node) ? :type : :method
        @response_builder.add_token(T.must(node.message_loc), type)
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
        return if @inside_implicit_node
        return unless visible?(node, @range)

        @response_builder.add_token(node.location, :namespace)
      end

      sig { params(node: Prism::ConstantWriteNode).void }
      def on_constant_write_node_enter(node)
        return unless visible?(node, @range)

        @response_builder.add_token(node.name_loc, :namespace)
      end

      sig { params(node: Prism::ConstantAndWriteNode).void }
      def on_constant_and_write_node_enter(node)
        return unless visible?(node, @range)

        @response_builder.add_token(node.name_loc, :namespace)
      end

      sig { params(node: Prism::ConstantOperatorWriteNode).void }
      def on_constant_operator_write_node_enter(node)
        return unless visible?(node, @range)

        @response_builder.add_token(node.name_loc, :namespace)
      end

      sig { params(node: Prism::ConstantOrWriteNode).void }
      def on_constant_or_write_node_enter(node)
        return unless visible?(node, @range)

        @response_builder.add_token(node.name_loc, :namespace)
      end

      sig { params(node: Prism::ConstantTargetNode).void }
      def on_constant_target_node_enter(node)
        return unless visible?(node, @range)

        @response_builder.add_token(node.location, :namespace)
      end

      sig { params(node: Prism::DefNode).void }
      def on_def_node_enter(node)
        @current_scope = ParameterScope.new(@current_scope)
        return unless visible?(node, @range)

        @response_builder.add_token(node.name_loc, :method, [:declaration])
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
        @response_builder.add_token(node.location, :variable)
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
        @response_builder.add_token(location.copy(length: location.length - 1), :parameter)
      end

      sig { params(node: Prism::OptionalKeywordParameterNode).void }
      def on_optional_keyword_parameter_node_enter(node)
        @current_scope << node.name
        return unless visible?(node, @range)

        location = node.name_loc
        @response_builder.add_token(location.copy(length: location.length - 1), :parameter)
      end

      sig { params(node: Prism::KeywordRestParameterNode).void }
      def on_keyword_rest_parameter_node_enter(node)
        name = node.name

        if name
          @current_scope << name.to_sym

          @response_builder.add_token(T.must(node.name_loc), :parameter) if visible?(node, @range)
        end
      end

      sig { params(node: Prism::OptionalParameterNode).void }
      def on_optional_parameter_node_enter(node)
        @current_scope << node.name
        return unless visible?(node, @range)

        @response_builder.add_token(node.name_loc, :parameter)
      end

      sig { params(node: Prism::RequiredParameterNode).void }
      def on_required_parameter_node_enter(node)
        @current_scope << node.name
        return unless visible?(node, @range)

        @response_builder.add_token(node.location, :parameter)
      end

      sig { params(node: Prism::RestParameterNode).void }
      def on_rest_parameter_node_enter(node)
        name = node.name

        if name
          @current_scope << name.to_sym

          @response_builder.add_token(T.must(node.name_loc), :parameter) if visible?(node, @range)
        end
      end

      sig { params(node: Prism::SelfNode).void }
      def on_self_node_enter(node)
        return unless visible?(node, @range)

        @response_builder.add_token(node.location, :variable, [:default_library])
      end

      sig { params(node: Prism::LocalVariableWriteNode).void }
      def on_local_variable_write_node_enter(node)
        return unless visible?(node, @range)

        @response_builder.add_token(node.name_loc, @current_scope.type_for(node.name))
      end

      sig { params(node: Prism::LocalVariableReadNode).void }
      def on_local_variable_read_node_enter(node)
        return if @inside_implicit_node
        return unless visible?(node, @range)

        # Numbered parameters
        if /_\d+/.match?(node.name)
          @response_builder.add_token(node.location, :parameter)
          return
        end

        @response_builder.add_token(node.location, @current_scope.type_for(node.name))
      end

      sig { params(node: Prism::LocalVariableAndWriteNode).void }
      def on_local_variable_and_write_node_enter(node)
        return unless visible?(node, @range)

        @response_builder.add_token(node.name_loc, @current_scope.type_for(node.name))
      end

      sig { params(node: Prism::LocalVariableOperatorWriteNode).void }
      def on_local_variable_operator_write_node_enter(node)
        return unless visible?(node, @range)

        @response_builder.add_token(node.name_loc, @current_scope.type_for(node.name))
      end

      sig { params(node: Prism::LocalVariableOrWriteNode).void }
      def on_local_variable_or_write_node_enter(node)
        return unless visible?(node, @range)

        @response_builder.add_token(node.name_loc, @current_scope.type_for(node.name))
      end

      sig { params(node: Prism::LocalVariableTargetNode).void }
      def on_local_variable_target_node_enter(node)
        # If we're inside a regex capture, Prism will add LocalVariableTarget nodes for each captured variable.
        # Unfortunately, if the regex contains a backslash, the location will be incorrect and we'll end up highlighting
        # the entire regex as a local variable. We process these captures in process_regexp_locals instead and then
        # prevent pushing local variable target tokens. See https://github.com/ruby/prism/issues/1912
        return if @inside_regex_capture

        return unless visible?(node, @range)

        @response_builder.add_token(node.location, @current_scope.type_for(node.name))
      end

      sig { params(node: Prism::ClassNode).void }
      def on_class_node_enter(node)
        return unless visible?(node, @range)

        @response_builder.add_token(node.constant_path.location, :class, [:declaration])

        superclass = node.superclass
        @response_builder.add_token(superclass.location, :class) if superclass
      end

      sig { params(node: Prism::ModuleNode).void }
      def on_module_node_enter(node)
        return unless visible?(node, @range)

        @response_builder.add_token(node.constant_path.location, :namespace, [:declaration])
      end

      sig { params(node: Prism::ImplicitNode).void }
      def on_implicit_node_enter(node)
        return unless visible?(node, @range)

        @inside_implicit_node = true
      end

      sig { params(node: Prism::ImplicitNode).void }
      def on_implicit_node_leave(node)
        @inside_implicit_node = false
      end

      private

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

          @response_builder.add_token(local_var_loc, @current_scope.type_for(name))
        end
      end
    end
  end
end
