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
          response_builder: ResponseBuilders::CollectionResponseBuilder[T.any(
            Interface::Location,
            Interface::LocationLink,
          )],
          global_state: GlobalState,
          language_id: Document::LanguageId,
          uri: URI::Generic,
          node_context: NodeContext,
          dispatcher: Prism::Dispatcher,
          sorbet_level: RubyDocument::SorbetLevel,
        ).void
      end
      def initialize(response_builder, global_state, language_id, uri, node_context, dispatcher, sorbet_level) # rubocop:disable Metrics/ParameterLists
        @response_builder = response_builder
        @global_state = global_state
        @index = T.let(global_state.index, RubyIndexer::Index)
        @type_inferrer = T.let(global_state.type_inferrer, TypeInferrer)
        @language_id = language_id
        @uri = uri
        @node_context = node_context
        @sorbet_level = sorbet_level

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
          :on_symbol_node_enter,
          :on_super_node_enter,
          :on_forwarding_super_node_enter,
        )
      end

      sig { params(node: Prism::CallNode).void }
      def on_call_node_enter(node)
        # Sorbet can handle go to definition for methods invoked on self on typed true or higher
        return if sorbet_level_true_or_higher?(@sorbet_level) && self_receiver?(node)

        message = node.message
        return unless message

        inferrer_receiver_type = @type_inferrer.infer_receiver_type(@node_context)

        # Until we can properly infer the receiver type in erb files (maybe with ruby-lsp-rails),
        # treating method calls' type as `nil` will allow users to get some completion support first
        if @language_id == Document::LanguageId::ERB && inferrer_receiver_type&.name == "Object"
          inferrer_receiver_type = nil
        end

        handle_method_definition(message, inferrer_receiver_type)
      end

      sig { params(node: Prism::StringNode).void }
      def on_string_node_enter(node)
        enclosing_call = @node_context.call_node
        return unless enclosing_call

        name = enclosing_call.name
        return unless name == :require || name == :require_relative

        handle_require_definition(node, name)
      end

      sig { params(node: Prism::SymbolNode).void }
      def on_symbol_node_enter(node)
        enclosing_call = @node_context.call_node
        return unless enclosing_call

        name = enclosing_call.name
        return unless name == :autoload

        handle_autoload_definition(enclosing_call)
      end

      sig { params(node: Prism::BlockArgumentNode).void }
      def on_block_argument_node_enter(node)
        expression = node.expression
        return unless expression.is_a?(Prism::SymbolNode)

        value = expression.value
        return unless value

        handle_method_definition(value, nil)
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

      sig { params(node: Prism::SuperNode).void }
      def on_super_node_enter(node)
        handle_super_node_definition
      end

      sig { params(node: Prism::ForwardingSuperNode).void }
      def on_forwarding_super_node_enter(node)
        handle_super_node_definition
      end

      private

      sig { void }
      def handle_super_node_definition
        # Sorbet can handle super hover on typed true or higher
        return if sorbet_level_true_or_higher?(@sorbet_level)

        surrounding_method = @node_context.surrounding_method
        return unless surrounding_method

        handle_method_definition(
          surrounding_method,
          @type_inferrer.infer_receiver_type(@node_context),
          inherited_only: true,
        )
      end

      sig { params(name: String).void }
      def handle_instance_variable_definition(name)
        # Sorbet enforces that all instance variables be declared on typed strict or higher, which means it will be able
        # to provide all features for them
        return if @sorbet_level == RubyDocument::SorbetLevel::Strict

        type = @type_inferrer.infer_receiver_type(@node_context)
        return unless type

        entries = @index.resolve_instance_variable(name, type.name)
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

      sig { params(message: String, receiver_type: T.nilable(TypeInferrer::Type), inherited_only: T::Boolean).void }
      def handle_method_definition(message, receiver_type, inherited_only: false)
        methods = if receiver_type
          @index.resolve_method(message, receiver_type.name, inherited_only: inherited_only)
        end

        # If the method doesn't have a receiver, or the guessed receiver doesn't have any matched candidates,
        # then we provide a few candidates to jump to
        # But we don't want to provide too many candidates, as it can be overwhelming
        if receiver_type.nil? || (receiver_type.is_a?(TypeInferrer::GuessedType) && methods.nil?)
          methods = @index[message]&.take(MAX_NUMBER_OF_DEFINITION_CANDIDATES_WITHOUT_RECEIVER)
        end

        return unless methods

        methods.each do |target_method|
          file_path = target_method.file_path
          next if sorbet_level_true_or_higher?(@sorbet_level) && not_in_dependencies?(file_path)

          @response_builder << Interface::LocationLink.new(
            target_uri: URI::Generic.from_path(path: file_path).to_s,
            target_range: range_from_location(target_method.location),
            target_selection_range: range_from_location(target_method.name_location),
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
          current_folder = path ? Pathname.new(CGI.unescape(path)).dirname : @global_state.workspace_path
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

      sig { params(node: Prism::CallNode).void }
      def handle_autoload_definition(node)
        argument = node.arguments&.arguments&.first
        return unless argument.is_a?(Prism::SymbolNode)

        constant_name = argument.value
        return unless constant_name

        find_in_index(constant_name)
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
          # If the project has Sorbet, then we only want to handle go to definition for constants defined in gems, as an
          # additional behavior on top of jumping to RBIs. The only sigil where Sorbet cannot handle constants is typed
          # ignore
          file_path = entry.file_path
          next if @sorbet_level != RubyDocument::SorbetLevel::Ignore && not_in_dependencies?(file_path)

          @response_builder << Interface::LocationLink.new(
            target_uri: URI::Generic.from_path(path: file_path).to_s,
            target_range: range_from_location(entry.location),
            target_selection_range: range_from_location(entry.name_location),
          )
        end
      end
    end
  end
end
