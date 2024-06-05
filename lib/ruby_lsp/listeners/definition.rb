# typed: strict
# frozen_string_literal: true

module RubyLsp
  module Listeners
    class Definition
      extend T::Sig
      include Requests::Support::Common

      MAX_NUMBER_OF_DEFINITION_CANDIDATES_WITHOUT_RECEIVER = 10

      sig do
        params(
          response_builder: ResponseBuilders::CollectionResponseBuilder[Interface::Location],
          global_state: GlobalState,
          uri: URI::Generic,
          node_context: NodeContext,
          dispatcher: Prism::Dispatcher,
          typechecker_enabled: T::Boolean,
        ).void
      end
      def initialize(response_builder, global_state, uri, node_context, dispatcher, typechecker_enabled) # rubocop:disable Metrics/ParameterLists
        @response_builder = response_builder
        @global_state = global_state
        @index = T.let(global_state.index, RubyIndexer::Index)
        @uri = uri
        @node_context = node_context
        @typechecker_enabled = typechecker_enabled

        dispatcher.register(
          self,
          :on_call_node_enter,
          :on_block_argument_node_enter,
          :on_constant_read_node_enter,
          :on_constant_path_node_enter,
          :on_instance_variable_read_node_enter,
          :on_instance_variable_write_node_enter,
          :on_instance_variable_and_write_node_enter,
          :on_instance_variable_operator_write_node_enter,
          :on_instance_variable_or_write_node_enter,
          :on_instance_variable_target_node_enter,
          :on_string_node_enter,
        )
      end

      sig { params(node: Prism::CallNode).void }
      def on_call_node_enter(node)
        message = node.message
        return unless message

        handle_method_definition(message, self_receiver?(node))
      end

      sig { params(node: Prism::StringNode).void }
      def on_string_node_enter(node)
        enclosing_call = @node_context.call_node
        return unless enclosing_call

        name = enclosing_call.name
        return unless name == :require || name == :require_relative

        handle_require_definition(node, name)
      end

      sig { params(node: Prism::BlockArgumentNode).void }
      def on_block_argument_node_enter(node)
        expression = node.expression
        return unless expression.is_a?(Prism::SymbolNode)

        value = expression.value
        return unless value

        handle_method_definition(value, false)
      end

      sig { params(node: Prism::ConstantPathNode).void }
      def on_constant_path_node_enter(node)
        name = constant_name(node)
        return if name.nil?

        find_in_index(name)
      end

      sig { params(node: Prism::ConstantReadNode).void }
      def on_constant_read_node_enter(node)
        name = constant_name(node)
        return if name.nil?

        find_in_index(name)
      end

      sig { params(node: Prism::InstanceVariableReadNode).void }
      def on_instance_variable_read_node_enter(node)
        handle_instance_variable_definition(node.name.to_s)
      end

      sig { params(node: Prism::InstanceVariableWriteNode).void }
      def on_instance_variable_write_node_enter(node)
        handle_instance_variable_definition(node.name.to_s)
      end

      sig { params(node: Prism::InstanceVariableAndWriteNode).void }
      def on_instance_variable_and_write_node_enter(node)
        handle_instance_variable_definition(node.name.to_s)
      end

      sig { params(node: Prism::InstanceVariableOperatorWriteNode).void }
      def on_instance_variable_operator_write_node_enter(node)
        handle_instance_variable_definition(node.name.to_s)
      end

      sig { params(node: Prism::InstanceVariableOrWriteNode).void }
      def on_instance_variable_or_write_node_enter(node)
        handle_instance_variable_definition(node.name.to_s)
      end

      sig { params(node: Prism::InstanceVariableTargetNode).void }
      def on_instance_variable_target_node_enter(node)
        handle_instance_variable_definition(node.name.to_s)
      end

      private

      sig { params(name: String).void }
      def handle_instance_variable_definition(name)
        entries = @index.resolve_instance_variable(name, @node_context.fully_qualified_name)
        return unless entries

        entries.each do |entry|
          location = entry.location

          @response_builder << Interface::Location.new(
            uri: URI::Generic.from_path(path: entry.file_path).to_s,
            range: Interface::Range.new(
              start: Interface::Position.new(line: location.start_line - 1, character: location.start_column),
              end: Interface::Position.new(line: location.end_line - 1, character: location.end_column),
            ),
          )
        end
      rescue RubyIndexer::Index::NonExistingNamespaceError
        # If by any chance we haven't indexed the owner, then there's no way to find the right declaration
      end

      sig { params(message: String, self_receiver: T::Boolean).void }
      def handle_method_definition(message, self_receiver)
        methods = if self_receiver
          @index.resolve_method(message, @node_context.fully_qualified_name)
        else
          # If the method doesn't have a receiver, then we provide a few candidates to jump to
          # But we don't want to provide too many candidates, as it can be overwhelming
          @index[message]&.take(MAX_NUMBER_OF_DEFINITION_CANDIDATES_WITHOUT_RECEIVER)
        end

        return unless methods

        methods.each do |target_method|
          location = target_method.location
          file_path = target_method.file_path
          next if @typechecker_enabled && not_in_dependencies?(file_path)

          @response_builder << Interface::Location.new(
            uri: URI::Generic.from_path(path: file_path).to_s,
            range: Interface::Range.new(
              start: Interface::Position.new(line: location.start_line - 1, character: location.start_column),
              end: Interface::Position.new(line: location.end_line - 1, character: location.end_column),
            ),
          )
        end
      end

      sig { params(node: Prism::StringNode, message: Symbol).void }
      def handle_require_definition(node, message)
        case message
        when :require
          entry = @index.search_require_paths(node.content).find do |indexable_path|
            indexable_path.require_path == node.content
          end

          if entry
            candidate = entry.full_path

            @response_builder << Interface::Location.new(
              uri: URI::Generic.from_path(path: candidate).to_s,
              range: Interface::Range.new(
                start: Interface::Position.new(line: 0, character: 0),
                end: Interface::Position.new(line: 0, character: 0),
              ),
            )
          end
        when :require_relative
          required_file = "#{node.content}.rb"
          path = @uri.to_standardized_path
          current_folder = path ? Pathname.new(CGI.unescape(path)).dirname : Dir.pwd
          candidate = File.expand_path(File.join(current_folder, required_file))

          @response_builder << Interface::Location.new(
            uri: URI::Generic.from_path(path: candidate).to_s,
            range: Interface::Range.new(
              start: Interface::Position.new(line: 0, character: 0),
              end: Interface::Position.new(line: 0, character: 0),
            ),
          )
        end
      end

      sig { params(value: String).void }
      def find_in_index(value)
        entries = @index.resolve(value, @node_context.nesting)
        return unless entries

        # We should only allow jumping to the definition of private constants if the constant is defined in the same
        # namespace as the reference
        first_entry = T.must(entries.first)
        return if first_entry.private? && first_entry.name != "#{@node_context.fully_qualified_name}::#{value}"

        entries.each do |entry|
          location = entry.location
          # If the project has Sorbet, then we only want to handle go to definition for constants defined in gems, as an
          # additional behavior on top of jumping to RBIs. Sorbet can already handle go to definition for all constants
          # in the project, even if the files are typed false
          file_path = entry.file_path
          next if @typechecker_enabled && not_in_dependencies?(file_path)

          @response_builder << Interface::Location.new(
            uri: URI::Generic.from_path(path: file_path).to_s,
            range: Interface::Range.new(
              start: Interface::Position.new(line: location.start_line - 1, character: location.start_column),
              end: Interface::Position.new(line: location.end_line - 1, character: location.end_column),
            ),
          )
        end
      end
    end
  end
end
