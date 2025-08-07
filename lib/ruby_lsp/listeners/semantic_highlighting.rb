# typed: strict
# frozen_string_literal: true

module RubyLsp
  module Listeners
    class SemanticHighlighting
      include Requests::Support::Common

      SPECIAL_RUBY_METHODS = [
        Module.instance_methods(false),
        Kernel.instance_methods(false),
        Kernel.methods(false),
        Bundler::Dsl.instance_methods(false),
        Module.private_instance_methods(false),
      ].flatten.map(&:to_s).freeze #: Array[String]

      #: (Prism::Dispatcher dispatcher, ResponseBuilders::SemanticHighlighting response_builder) -> void
      def initialize(dispatcher, response_builder)
        @response_builder = response_builder
        @special_methods = nil #: Array[String]?
        @current_scope = Scope.new #: Scope
        @inside_regex_capture = false #: bool
        @inside_implicit_node = false #: bool

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

      #: (Prism::CallNode node) -> void
      def on_call_node_enter(node)
        return if @inside_implicit_node

        message = node.message
        return unless message

        # We can't push a semantic token for [] and []= because the argument inside the brackets is a part of
        # the message_loc
        return if message.start_with?("[") && (message.end_with?("]") || message.end_with?("]="))
        return if message == "=~"
        return if special_method?(message)

        if Requests::Support::Sorbet.annotation?(node)
          @response_builder.add_token(
            node.message_loc, #: as !nil
            :type,
          )
        elsif !node.receiver && !node.opening_loc
          # If the node has a receiver, then the syntax is not ambiguous and semantic highlighting is not necessary to
          # determine that the token is a method call. The only ambiguous case is method calls with implicit self
          # receiver and no parenthesis, which may be confused with local variables
          @response_builder.add_token(
            node.message_loc, #: as !nil
            :method,
          )
        end
      end

      #: (Prism::MatchWriteNode node) -> void
      def on_match_write_node_enter(node)
        call = node.call

        if call.message == "=~"
          @inside_regex_capture = true
          process_regexp_locals(call)
        end
      end

      #: (Prism::MatchWriteNode node) -> void
      def on_match_write_node_leave(node)
        @inside_regex_capture = true if node.call.message == "=~"
      end

      #: (Prism::DefNode node) -> void
      def on_def_node_enter(node)
        @current_scope = Scope.new(@current_scope)
      end

      #: (Prism::DefNode node) -> void
      def on_def_node_leave(node)
        @current_scope = @current_scope.parent #: as !nil
      end

      #: (Prism::BlockNode node) -> void
      def on_block_node_enter(node)
        @current_scope = Scope.new(@current_scope)
      end

      #: (Prism::BlockNode node) -> void
      def on_block_node_leave(node)
        @current_scope = @current_scope.parent #: as !nil
      end

      #: (Prism::BlockLocalVariableNode node) -> void
      def on_block_local_variable_node_enter(node)
        @response_builder.add_token(node.location, :variable)
      end

      #: (Prism::BlockParameterNode node) -> void
      def on_block_parameter_node_enter(node)
        name = node.name
        @current_scope.add(name.to_sym, :parameter) if name
      end

      #: (Prism::RequiredKeywordParameterNode node) -> void
      def on_required_keyword_parameter_node_enter(node)
        @current_scope.add(node.name, :parameter)
      end

      #: (Prism::OptionalKeywordParameterNode node) -> void
      def on_optional_keyword_parameter_node_enter(node)
        @current_scope.add(node.name, :parameter)
      end

      #: (Prism::KeywordRestParameterNode node) -> void
      def on_keyword_rest_parameter_node_enter(node)
        name = node.name
        @current_scope.add(name.to_sym, :parameter) if name
      end

      #: (Prism::OptionalParameterNode node) -> void
      def on_optional_parameter_node_enter(node)
        @current_scope.add(node.name, :parameter)
      end

      #: (Prism::RequiredParameterNode node) -> void
      def on_required_parameter_node_enter(node)
        @current_scope.add(node.name, :parameter)
      end

      #: (Prism::RestParameterNode node) -> void
      def on_rest_parameter_node_enter(node)
        name = node.name
        @current_scope.add(name.to_sym, :parameter) if name
      end

      #: (Prism::SelfNode node) -> void
      def on_self_node_enter(node)
        @response_builder.add_token(node.location, :variable, [:default_library])
      end

      #: (Prism::LocalVariableWriteNode node) -> void
      def on_local_variable_write_node_enter(node)
        local = @current_scope.lookup(node.name)
        @response_builder.add_token(node.name_loc, :parameter) if local&.type == :parameter
      end

      #: (Prism::LocalVariableReadNode node) -> void
      def on_local_variable_read_node_enter(node)
        return if @inside_implicit_node

        # Numbered parameters
        if /_\d+/.match?(node.name)
          @response_builder.add_token(node.location, :parameter)
          return
        end

        local = @current_scope.lookup(node.name)
        @response_builder.add_token(node.location, local&.type || :variable)
      end

      #: (Prism::LocalVariableAndWriteNode node) -> void
      def on_local_variable_and_write_node_enter(node)
        local = @current_scope.lookup(node.name)
        @response_builder.add_token(node.name_loc, :parameter) if local&.type == :parameter
      end

      #: (Prism::LocalVariableOperatorWriteNode node) -> void
      def on_local_variable_operator_write_node_enter(node)
        local = @current_scope.lookup(node.name)
        @response_builder.add_token(node.name_loc, :parameter) if local&.type == :parameter
      end

      #: (Prism::LocalVariableOrWriteNode node) -> void
      def on_local_variable_or_write_node_enter(node)
        local = @current_scope.lookup(node.name)
        @response_builder.add_token(node.name_loc, :parameter) if local&.type == :parameter
      end

      #: (Prism::LocalVariableTargetNode node) -> void
      def on_local_variable_target_node_enter(node)
        # If we're inside a regex capture, Prism will add LocalVariableTarget nodes for each captured variable.
        # Unfortunately, if the regex contains a backslash, the location will be incorrect and we'll end up highlighting
        # the entire regex as a local variable. We process these captures in process_regexp_locals instead and then
        # prevent pushing local variable target tokens. See https://github.com/ruby/prism/issues/1912
        return if @inside_regex_capture

        local = @current_scope.lookup(node.name)
        @response_builder.add_token(node.location, local&.type || :variable)
      end

      #: (Prism::ClassNode node) -> void
      def on_class_node_enter(node)
        constant_path = node.constant_path

        if constant_path.is_a?(Prism::ConstantReadNode)
          @response_builder.add_token(constant_path.location, :class, [:declaration])
        else
          each_constant_path_part(constant_path) do |part|
            loc = case part
            when Prism::ConstantPathNode
              part.name_loc
            when Prism::ConstantReadNode
              part.location
            end
            next unless loc

            @response_builder.add_token(loc, :class, [:declaration])
          end
        end

        superclass = node.superclass

        if superclass.is_a?(Prism::ConstantReadNode)
          @response_builder.add_token(superclass.location, :class)
        elsif superclass
          each_constant_path_part(superclass) do |part|
            loc = case part
            when Prism::ConstantPathNode
              part.name_loc
            when Prism::ConstantReadNode
              part.location
            end
            next unless loc

            @response_builder.add_token(loc, :class)
          end
        end
      end

      #: (Prism::ModuleNode node) -> void
      def on_module_node_enter(node)
        constant_path = node.constant_path

        if constant_path.is_a?(Prism::ConstantReadNode)
          @response_builder.add_token(constant_path.location, :namespace, [:declaration])
        else
          each_constant_path_part(constant_path) do |part|
            loc = case part
            when Prism::ConstantPathNode
              part.name_loc
            when Prism::ConstantReadNode
              part.location
            end
            next unless loc

            @response_builder.add_token(loc, :namespace, [:declaration])
          end
        end
      end

      #: (Prism::ImplicitNode node) -> void
      def on_implicit_node_enter(node)
        @inside_implicit_node = true
      end

      #: (Prism::ImplicitNode node) -> void
      def on_implicit_node_leave(node)
        @inside_implicit_node = false
      end

      private

      # Textmate provides highlighting for a subset of these special Ruby-specific methods.  We want to utilize that
      # highlighting, so we avoid making a semantic token for it.
      #: (String method_name) -> bool
      def special_method?(method_name)
        SPECIAL_RUBY_METHODS.include?(method_name)
      end

      #: (Prism::CallNode node) -> void
      def process_regexp_locals(node)
        receiver = node.receiver

        # The regexp needs to be the receiver of =~ for local variable capture
        return unless receiver.is_a?(Prism::RegularExpressionNode)

        content = receiver.content
        loc = receiver.content_loc

        # For each capture name we find in the regexp, look for a local in the current_scope
        Regexp.new(content, Regexp::FIXEDENCODING).names.each do |name|
          # The +3 is to compensate for the "(?<" part of the capture name
          capture_name_index = content.index("(?<#{name}>") #: as !nil
          capture_name_offset = capture_name_index + 3
          local_var_loc = loc.copy(start_offset: loc.start_offset + capture_name_offset, length: name.length)

          local = @current_scope.lookup(name)
          @response_builder.add_token(local_var_loc, local&.type || :variable)
        end
      end
    end
  end
end
