# typed: strict
# frozen_string_literal: true

module RubyLsp
  module Requests
    # The
    # [references](https://microsoft.github.io/language-server-protocol/specification#textDocument_references)
    # request finds all references for the selected symbol.
    class References < Request
      include Support::Common

      MAX_NUMBER_OF_METHOD_CANDIDATES_WITHOUT_RECEIVER = 30

      #: (GlobalState global_state, Store store, (RubyDocument | ERBDocument) document, Hash[Symbol, untyped] params) -> void
      def initialize(global_state, store, document, params)
        super()
        @global_state = global_state
        @type_inferrer = global_state.type_inferrer #: TypeInferrer
        @graph = global_state.graph #: Rubydex::Graph
        @store = store
        @document = document
        @params = params
        @locations = [] #: Array[Interface::Location]
        @char_position = 0 #: Integer
      end

      # @override
      #: -> Array[Interface::Location]
      def perform
        include_declarations = @params.dig(:context, :includeDeclaration) || false
        @char_position, _ = @document.find_index_by_position(@params[:position])

        node_context = RubyDocument.locate(
          @document.ast,
          @char_position,
          node_types: [
            Prism::ConstantReadNode,
            Prism::ConstantPathNode,
            Prism::ConstantPathTargetNode,
            Prism::ConstantAndWriteNode,
            Prism::ConstantOperatorWriteNode,
            Prism::ConstantOrWriteNode,
            Prism::ConstantTargetNode,
            Prism::ConstantWriteNode,
            Prism::InstanceVariableAndWriteNode,
            Prism::InstanceVariableOperatorWriteNode,
            Prism::InstanceVariableOrWriteNode,
            Prism::InstanceVariableReadNode,
            Prism::InstanceVariableTargetNode,
            Prism::InstanceVariableWriteNode,
            Prism::ClassVariableAndWriteNode,
            Prism::ClassVariableOperatorWriteNode,
            Prism::ClassVariableOrWriteNode,
            Prism::ClassVariableReadNode,
            Prism::ClassVariableTargetNode,
            Prism::ClassVariableWriteNode,
            Prism::GlobalVariableAndWriteNode,
            Prism::GlobalVariableOperatorWriteNode,
            Prism::GlobalVariableOrWriteNode,
            Prism::GlobalVariableReadNode,
            Prism::GlobalVariableTargetNode,
            Prism::GlobalVariableWriteNode,
            Prism::CallNode,
            Prism::CallAndWriteNode,
            Prism::CallOperatorWriteNode,
            Prism::CallOrWriteNode,
            Prism::DefNode,
          ],
          code_units_cache: @document.code_units_cache,
        )
        target = node_context.node
        return @locations if !target || target.is_a?(Prism::ProgramNode)

        case target
        when Prism::ConstantReadNode, Prism::ConstantPathNode, Prism::ConstantPathTargetNode
          name = constant_name(target)
          handle_constant_references(name, node_context, include_declarations) if name
        when Prism::ConstantTargetNode
          handle_constant_references(target.name.to_s, node_context, include_declarations)
        when Prism::ConstantAndWriteNode, Prism::ConstantOperatorWriteNode, Prism::ConstantOrWriteNode,
          Prism::ConstantWriteNode
          if cursor_on_name?(target.name_loc)
            handle_constant_references(target.name.to_s, node_context, include_declarations)
          end
        when Prism::InstanceVariableReadNode, Prism::InstanceVariableTargetNode,
          Prism::ClassVariableReadNode, Prism::ClassVariableTargetNode
          handle_variable_references(target.name.to_s, node_context, include_declarations)
        when Prism::InstanceVariableAndWriteNode, Prism::InstanceVariableOperatorWriteNode,
          Prism::InstanceVariableOrWriteNode, Prism::InstanceVariableWriteNode,
          Prism::ClassVariableAndWriteNode, Prism::ClassVariableOperatorWriteNode,
          Prism::ClassVariableOrWriteNode, Prism::ClassVariableWriteNode
          if cursor_on_name?(target.name_loc)
            handle_variable_references(target.name.to_s, node_context, include_declarations)
          end
        when Prism::GlobalVariableReadNode, Prism::GlobalVariableTargetNode
          handle_global_variable_references(target.name.to_s, include_declarations)
        when Prism::GlobalVariableAndWriteNode, Prism::GlobalVariableOperatorWriteNode,
          Prism::GlobalVariableOrWriteNode, Prism::GlobalVariableWriteNode
          if cursor_on_name?(target.name_loc)
            handle_global_variable_references(target.name.to_s, include_declarations)
          end
        when Prism::CallNode
          message_loc = target.message_loc
          message = target.message
          if message && message_loc && cursor_on_name?(message_loc)
            resolve_method_references(message, node_context, include_declarations)
          end
        when Prism::CallAndWriteNode, Prism::CallOperatorWriteNode, Prism::CallOrWriteNode
          message_loc = target.message_loc
          if message_loc && cursor_on_name?(message_loc)
            resolve_method_references(target.read_name.to_s, node_context, include_declarations)
          end
        when Prism::DefNode
          handle_def_node_references(target, node_context, include_declarations) if cursor_on_name?(target.name_loc)
        end

        @locations
      end

      private

      #: (String name, NodeContext node_context, bool include_declarations) -> void
      def handle_constant_references(name, node_context, include_declarations)
        declaration = @graph.resolve_constant(name, node_context.nesting)
        return unless declaration

        collect_references(declaration.references, [declaration], include_declarations)
      end

      #: (String message, NodeContext node_context, bool include_declarations) -> void
      def resolve_method_references(message, node_context, include_declarations)
        receiver_type = @type_inferrer.infer_receiver_type(node_context)

        declaration = if receiver_type
          owner = @graph[receiver_type.name]
          owner.find_member("#{message}()") if owner.is_a?(Rubydex::Namespace)
        end

        declarations = if receiver_type.nil? || (receiver_type.is_a?(TypeInferrer::GuessedType) && declaration.nil?)
          @graph.search("##{message}()").take(MAX_NUMBER_OF_METHOD_CANDIDATES_WITHOUT_RECEIVER)
        elsif declaration
          [declaration]
        else
          []
        end
        return if declarations.empty?

        collect_references(method_references_for(message), declarations, include_declarations)
      end

      # Handles instance and class variable references. Resolves the receiver type from the node context to locate
      # the owning namespace, then looks up the member through the ancestor chain via `find_member`.
      #: (String name, NodeContext node_context, bool include_declarations) -> void
      def handle_variable_references(name, node_context, include_declarations)
        type = @type_inferrer.infer_receiver_type(node_context)
        return unless type

        owner = @graph[type.name]
        return unless owner.is_a?(Rubydex::Namespace)

        declaration = owner.find_member(name)
        return unless declaration

        collect_references(declaration.references, [declaration], include_declarations)
      end

      # Handles global variable references. Globals are keyed by their full name (including `$`) in the graph, so we
      # can look them up directly without needing to resolve a receiver type.
      #: (String name, bool include_declarations) -> void
      def handle_global_variable_references(name, include_declarations)
        declaration = @graph[name]
        return unless declaration

        collect_references(declaration.references, [declaration], include_declarations)
      end

      #: (Prism::DefNode target, NodeContext node_context, bool include_declarations) -> void
      def handle_def_node_references(target, node_context, include_declarations)
        method_name = target.name.to_s

        owner_type = @type_inferrer.infer_receiver_type(node_context)
        return unless owner_type

        owner = @graph[owner_type.name]
        return unless owner.is_a?(Rubydex::Namespace)

        declaration = owner.find_member("#{method_name}()")
        return unless declaration

        collect_references(method_references_for(method_name), [declaration], include_declarations)
      end

      # Method references in Rubydex are not yet resolved to specific declarations, so we filter from the global
      # method references by name
      #: (String) -> Array[Rubydex::MethodReference]
      def method_references_for(method_name)
        @graph.method_references.select { |reference| reference.name == method_name }
      end

      #: (Enumerable[Rubydex::Reference] references, Array[Rubydex::Declaration] declarations, bool include_declarations) -> void
      def collect_references(references, declarations, include_declarations)
        references.each do |reference|
          next if rubydex_internal_uri?(reference.location.uri)

          @locations << reference.to_lsp_location
        end

        return unless include_declarations

        declarations.each do |declaration|
          declaration.definitions.each do |definition|
            next if rubydex_internal_uri?(definition.location.uri)

            @locations << definition.to_lsp_selection_location
          end
        end
      end

      #: (String uri) -> bool
      def rubydex_internal_uri?(uri)
        URI(uri).scheme == "rubydex"
      end

      # Write, operator-write, and call-with-message nodes cover more than just the identifier —
      # they span the whole assignment or call expression. We only resolve references when the
      # cursor is positioned directly on the name itself, not on operators, values, or arguments.
      #: (Prism::Location name_loc) -> bool
      def cursor_on_name?(name_loc)
        start = name_loc.cached_start_code_units_offset(@document.code_units_cache)
        finish = name_loc.cached_end_code_units_offset(@document.code_units_cache)
        (start...finish).cover?(@char_position)
      end
    end
  end
end
