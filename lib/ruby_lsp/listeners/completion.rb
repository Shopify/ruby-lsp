# typed: strict
# frozen_string_literal: true

module RubyLsp
  module Listeners
    class Completion
      include Requests::Support::Common

      #: (ResponseBuilders::CollectionResponseBuilder[Interface::CompletionItem] response_builder, GlobalState global_state, NodeContext node_context, SorbetLevel sorbet_level, Prism::Dispatcher dispatcher, URI::Generic uri, String? trigger_character) -> void
      def initialize( # rubocop:disable Metrics/ParameterLists
        response_builder,
        global_state,
        node_context,
        sorbet_level,
        dispatcher,
        uri,
        trigger_character
      )
        @response_builder = response_builder
        @global_state = global_state
        @graph = global_state.graph #: Rubydex::Graph
        @type_inferrer = global_state.type_inferrer #: TypeInferrer
        @node_context = node_context
        @sorbet_level = sorbet_level
        @uri = uri
        @trigger_character = trigger_character

        dispatcher.register(
          self,
          :on_constant_path_node_enter,
          :on_constant_read_node_enter,
          :on_call_node_enter,
          :on_global_variable_and_write_node_enter,
          :on_global_variable_operator_write_node_enter,
          :on_global_variable_or_write_node_enter,
          :on_global_variable_read_node_enter,
          :on_global_variable_target_node_enter,
          :on_global_variable_write_node_enter,
          :on_instance_variable_read_node_enter,
          :on_instance_variable_write_node_enter,
          :on_instance_variable_and_write_node_enter,
          :on_instance_variable_operator_write_node_enter,
          :on_instance_variable_or_write_node_enter,
          :on_instance_variable_target_node_enter,
          :on_class_variable_and_write_node_enter,
          :on_class_variable_operator_write_node_enter,
          :on_class_variable_or_write_node_enter,
          :on_class_variable_read_node_enter,
          :on_class_variable_target_node_enter,
          :on_class_variable_write_node_enter,
        )
      end

      # Handle completion on regular constant references (e.g. `Bar`)
      #: (Prism::ConstantReadNode node) -> void
      def on_constant_read_node_enter(node)
        # The only scenario where Sorbet doesn't provide constant completion is on ignored files. Even if the file has
        # no sigil, Sorbet will still provide completion for constants
        return unless @sorbet_level.ignore?

        name = constant_name(node)
        return if name.nil?

        complete_constants(range_from_location(node.location), name)
      end

      # Handle completion on namespaced constant references (e.g. `Foo::Bar`)
      #: (Prism::ConstantPathNode node) -> void
      def on_constant_path_node_enter(node)
        # The only scenario where Sorbet doesn't provide constant completion is on ignored files. Even if the file has
        # no sigil, Sorbet will still provide completion for constants
        return unless @sorbet_level.ignore?

        name = begin
          node.full_name
        rescue Prism::ConstantPathNode::MissingNodesInConstantPathError
          node.slice
        rescue Prism::ConstantPathNode::DynamicPartsInConstantPathError
          nil
        end
        return if name.nil?

        constant_path_completion(name, range_from_location(node.location))
      end

      #: (Prism::CallNode node) -> void
      def on_call_node_enter(node)
        # The only scenario where Sorbet doesn't provide constant completion is on ignored files. Even if the file has
        # no sigil, Sorbet will still provide completion for constants
        if @sorbet_level.ignore?
          receiver = node.receiver

          # When writing `Foo::`, the AST assigns a method call node (because you can use that syntax to invoke
          # singleton methods). However, in addition to providing method completion, we also need to show possible
          # constant completions
          if (receiver.is_a?(Prism::ConstantReadNode) || receiver.is_a?(Prism::ConstantPathNode)) &&
              node.call_operator == "::"

            name = constant_name(receiver)

            if name
              start_loc = node.location
              end_loc = node.call_operator_loc #: as !nil

              constant_path_completion(
                "#{name}::",
                Interface::Range.new(
                  start: Interface::Position.new(line: start_loc.start_line - 1, character: start_loc.start_column),
                  end: Interface::Position.new(line: end_loc.end_line - 1, character: end_loc.end_column),
                ),
              )
              return
            end
          end
        end

        name = node.message
        return unless name

        case name
        when "require"
          complete_require(node)
        when "require_relative"
          complete_require_relative(node)
        else
          if node.receiver
            complete_method_call(node, name)
          else
            # Sorbet provides method-on-self completion for any file with a Sorbet level of true or higher
            return if @sorbet_level.true_or_higher?

            message_loc = node.message_loc #: as !nil
            complete_methods_no_receiver(range_from_location(message_loc), name)
          end
        end
      end

      #: (Prism::GlobalVariableAndWriteNode node) -> void
      def on_global_variable_and_write_node_enter(node)
        complete_variable(range_from_location(node.name_loc), node.name.to_s)
      end

      #: (Prism::GlobalVariableOperatorWriteNode node) -> void
      def on_global_variable_operator_write_node_enter(node)
        complete_variable(range_from_location(node.name_loc), node.name.to_s)
      end

      #: (Prism::GlobalVariableOrWriteNode node) -> void
      def on_global_variable_or_write_node_enter(node)
        complete_variable(range_from_location(node.name_loc), node.name.to_s)
      end

      #: (Prism::GlobalVariableReadNode node) -> void
      def on_global_variable_read_node_enter(node)
        complete_variable(range_from_location(node.location), node.name.to_s)
      end

      #: (Prism::GlobalVariableTargetNode node) -> void
      def on_global_variable_target_node_enter(node)
        complete_variable(range_from_location(node.location), node.name.to_s)
      end

      #: (Prism::GlobalVariableWriteNode node) -> void
      def on_global_variable_write_node_enter(node)
        complete_variable(range_from_location(node.name_loc), node.name.to_s)
      end

      #: (Prism::InstanceVariableReadNode node) -> void
      def on_instance_variable_read_node_enter(node)
        return if @sorbet_level.strict?

        complete_variable(range_from_location(node.location), node.name.to_s)
      end

      #: (Prism::InstanceVariableWriteNode node) -> void
      def on_instance_variable_write_node_enter(node)
        return if @sorbet_level.strict?

        complete_variable(range_from_location(node.name_loc), node.name.to_s)
      end

      #: (Prism::InstanceVariableAndWriteNode node) -> void
      def on_instance_variable_and_write_node_enter(node)
        return if @sorbet_level.strict?

        complete_variable(range_from_location(node.name_loc), node.name.to_s)
      end

      #: (Prism::InstanceVariableOperatorWriteNode node) -> void
      def on_instance_variable_operator_write_node_enter(node)
        return if @sorbet_level.strict?

        complete_variable(range_from_location(node.name_loc), node.name.to_s)
      end

      #: (Prism::InstanceVariableOrWriteNode node) -> void
      def on_instance_variable_or_write_node_enter(node)
        return if @sorbet_level.strict?

        complete_variable(range_from_location(node.name_loc), node.name.to_s)
      end

      #: (Prism::InstanceVariableTargetNode node) -> void
      def on_instance_variable_target_node_enter(node)
        return if @sorbet_level.strict?

        complete_variable(range_from_location(node.location), node.name.to_s)
      end

      #: (Prism::ClassVariableAndWriteNode node) -> void
      def on_class_variable_and_write_node_enter(node)
        return if @sorbet_level.strict?

        complete_variable(range_from_location(node.name_loc), node.name.to_s)
      end

      #: (Prism::ClassVariableOperatorWriteNode node) -> void
      def on_class_variable_operator_write_node_enter(node)
        return if @sorbet_level.strict?

        complete_variable(range_from_location(node.name_loc), node.name.to_s)
      end

      #: (Prism::ClassVariableOrWriteNode node) -> void
      def on_class_variable_or_write_node_enter(node)
        return if @sorbet_level.strict?

        complete_variable(range_from_location(node.name_loc), node.name.to_s)
      end

      #: (Prism::ClassVariableTargetNode node) -> void
      def on_class_variable_target_node_enter(node)
        return if @sorbet_level.strict?

        complete_variable(range_from_location(node.location), node.name.to_s)
      end

      #: (Prism::ClassVariableReadNode node) -> void
      def on_class_variable_read_node_enter(node)
        return if @sorbet_level.strict?

        complete_variable(range_from_location(node.location), node.name.to_s)
      end

      #: (Prism::ClassVariableWriteNode node) -> void
      def on_class_variable_write_node_enter(node)
        return if @sorbet_level.strict?

        complete_variable(range_from_location(node.name_loc), node.name.to_s)
      end

      private

      # Returns every candidate reachable from the current scope (constants, methods, ivars, cvars, globals, keywords).
      # Specialized completion methods filter by node kind and prefix.
      #
      #: () -> Array[(Rubydex::Declaration | Rubydex::Keyword)]
      def expression_candidates
        @graph.complete_expression(@node_context.nesting, self_receiver: nil)
      end

      #: (Interface::Range range, String prefix) -> void
      def complete_constants(range, prefix)
        expression_candidates.each do |candidate|
          next unless candidate.is_a?(Rubydex::Class) || candidate.is_a?(Rubydex::Module) ||
            candidate.is_a?(Rubydex::Constant) || candidate.is_a?(Rubydex::ConstantAlias)

          # Match either the short (unqualified) or fully qualified name, so that lexically-reachable constants like
          # `Foo::CONST` match when the user types `CONST` and fully-qualified typing like `Foo::CONST` still matches
          complete_name = candidate.name
          next unless candidate.unqualified_name.start_with?(prefix) || complete_name.start_with?(prefix)

          @response_builder << build_entry_completion(complete_name, prefix, range, candidate)
        end
      end

      #: (Interface::Range range, String prefix) -> void
      def complete_methods_no_receiver(range, prefix)
        @node_context.locals_for_scope.each do |local|
          local_name = local.to_s
          next unless local_name.start_with?(prefix)

          @response_builder << Interface::CompletionItem.new(
            label: local_name,
            filter_text: local_name,
            text_edit: Interface::TextEdit.new(range: range, new_text: local_name),
            kind: Constant::CompletionItemKind::VARIABLE,
            data: { skip_resolve: true },
          )
        end

        expression_candidates.each do |candidate|
          case candidate
          when Rubydex::Method
            display_name = candidate.unqualified_name.delete_suffix("()")
            next unless display_name.start_with?(prefix)

            add_method_completion(candidate, range)
          when Rubydex::Keyword
            next unless candidate.name.start_with?(prefix)

            @response_builder << Interface::CompletionItem.new(
              label: candidate.name,
              text_edit: Interface::TextEdit.new(range: range, new_text: candidate.name),
              kind: Constant::CompletionItemKind::KEYWORD,
              data: { keyword: true },
            )
          end
        end
      end

      # Namespace access (e.g.: `Foo::Bar`, `::Bar`). Collects all constants for the namespace that the prefix resolves
      # to, preserving any alias names typed by the user
      #: (String name, Interface::Range range) -> void
      def constant_path_completion(name, range)
        if name.end_with?("::")
          namespace_prefix = name.delete_suffix("::")
          incomplete_name = nil
        else
          *segments, incomplete_name = name.split("::")
          namespace_prefix = segments.join("::")
        end

        candidates = if namespace_prefix.empty?
          @graph.complete_expression([], self_receiver: nil)
        else
          # Rubydex's resolver handles a leading `::` on `namespace_prefix` by resolving from the top-level scope, so
          # we don't need to special-case top-level references here
          resolved = @graph.resolve_constant(namespace_prefix, @node_context.nesting)
          return unless resolved

          @graph.complete_namespace_access(resolved.name, self_receiver: nil)
        end

        candidates.each do |candidate|
          next unless candidate.is_a?(Rubydex::Class) || candidate.is_a?(Rubydex::Module) ||
            candidate.is_a?(Rubydex::Constant) || candidate.is_a?(Rubydex::ConstantAlias)

          short_name = candidate.unqualified_name
          next if incomplete_name && !short_name.start_with?(incomplete_name)

          full_name = namespace_prefix.empty? ? short_name : "#{namespace_prefix}::#{short_name}"
          @response_builder << build_entry_completion(full_name, name, range, candidate)
        end
      end

      # Method call on a receiver (e.g.: `foo.`, `@bar.`, `@@baz.`, `Qux.`). Collects all methods that exist on the
      # type returned by the receiver, filtered by the prefix typed
      #: (Prism::CallNode node, String name) -> void
      def complete_method_call(node, name)
        # Sorbet can provide completion for methods invoked on self on typed true or higher files
        return if @sorbet_level.true_or_higher? && self_receiver?(node)

        type = @type_inferrer.infer_receiver_type(@node_context)
        return unless type

        # When the trigger character is a dot, Prism matches the name of the call node to whatever is next in the
        # source code, leading to us searching for the wrong name. What we want to do instead is show every available
        # method when dot is pressed
        method_name = @trigger_character == "." ? nil : name

        range = if method_name
          range_from_location(
            node.message_loc, #: as !nil
          )
        else
          loc = node.call_operator_loc

          if loc
            Interface::Range.new(
              start: Interface::Position.new(line: loc.start_line - 1, character: loc.start_column + 1),
              end: Interface::Position.new(line: loc.start_line - 1, character: loc.start_column + 1),
            )
          end
        end

        return unless range

        guessed_type = type.is_a?(TypeInferrer::GuessedType) && type.name

        @graph.complete_method_call(type.name, self_receiver: nil).each do |candidate|
          if method_name
            display_name = candidate.unqualified_name.delete_suffix("()")
            next unless display_name.start_with?(method_name)
          end

          add_method_completion(candidate, range, has_receiver: true, guessed_type: guessed_type)
        end
      end

      # Variable completion (instance, class, and global). The variable kind is selected by the prefix the user typed:
      # `$…` only matches globals, `@@…` only class variables, and `@…` matches both instance and class variables (since
      # `@@foo`.start_with?("@") is true). Globals live at top-level, so they need an empty nesting; instance/class
      # variables resolve through the type_inferrer to handle singleton methods and class bodies, where the receiver is
      # the singleton class rather than the lexical nesting.
      #
      #: (Interface::Range, String) -> void
      def complete_variable(range, prefix)
        type = @type_inferrer.infer_receiver_type(@node_context)
        nesting = type ? type.name.split("::") : []

        @graph.complete_expression(nesting, self_receiver: nil).each do |candidate|
          next unless candidate.is_a?(Rubydex::Declaration)

          variable_name = candidate.unqualified_name
          next unless variable_name.start_with?(prefix)

          @response_builder << Interface::CompletionItem.new(
            label: variable_name,
            label_details: Interface::CompletionItemLabelDetails.new(
              description: declaration_file_names(candidate),
            ),
            text_edit: Interface::TextEdit.new(range: range, new_text: variable_name),
            kind: candidate.to_lsp_completion_kind,
            data: { owner_name: candidate.owner.name },
          )
        end
      end

      #: (Prism::CallNode node) -> void
      def complete_require(node)
        arguments_node = node.arguments
        return unless arguments_node

        path_node_to_complete = arguments_node.arguments.first

        return unless path_node_to_complete.is_a?(Prism::StringNode)

        content = path_node_to_complete.content

        @graph.require_paths($LOAD_PATH).select { |path| path.start_with?(content) }.sort!.each do |path|
          @response_builder << build_completion(path, path_node_to_complete)
        end
      end

      #: (Prism::CallNode node) -> void
      def complete_require_relative(node)
        arguments_node = node.arguments
        return unless arguments_node

        path_node_to_complete = arguments_node.arguments.first
        return unless path_node_to_complete.is_a?(Prism::StringNode)

        # If the file is unsaved (e.g.: untitled:Untitled-1), we can't provide relative completion as we don't know
        # where the user intends to save it
        full_path = @uri.to_standardized_path
        return unless full_path

        origin_dir = Pathname.new(full_path).dirname
        content = path_node_to_complete.content
        # if the path is not a directory, glob all possible next characters
        # for example ../somethi| (where | is the cursor position)
        # should find files for ../somethi*/
        path_query = if content.end_with?("/") || content.empty?
          "#{content}**/*.rb"
        else
          "{#{content}*/**/*.rb,**/#{content}*.rb}"
        end

        Dir.glob(path_query, File::FNM_PATHNAME | File::FNM_EXTGLOB, base: origin_dir).sort!.each do |path|
          @response_builder << build_completion(
            path.delete_suffix(".rb"),
            path_node_to_complete,
          )
        end
      rescue Errno::EPERM
        # If the user writes a relative require pointing to a path that the editor has no permissions to read, then glob
        # might fail with EPERM
      end

      #: (Rubydex::Method candidate, Interface::Range range, ?has_receiver: bool, ?guessed_type: (String | bool)) -> void
      def add_method_completion(candidate, range, has_receiver: false, guessed_type: false)
        display_name = candidate.unqualified_name.delete_suffix("()")
        new_text = display_name

        if display_name.end_with?("=")
          setter_name = display_name.delete_suffix("=")

          # For writer methods, format as assignment and prefix "self." when no receiver is specified
          new_text = has_receiver ? "#{setter_name} = " : "self.#{setter_name} = "
        end

        @response_builder << Interface::CompletionItem.new(
          label: display_name,
          filter_text: display_name,
          label_details: Interface::CompletionItemLabelDetails.new(description: declaration_file_names(candidate)),
          text_edit: Interface::TextEdit.new(range: range, new_text: new_text),
          kind: candidate.to_lsp_completion_kind,
          data: { owner_name: candidate.owner.name, guessed_type: guessed_type },
        )
      end

      #: (String label, Prism::StringNode node) -> Interface::CompletionItem
      def build_completion(label, node)
        # We should use the content location as we only replace the content and not the delimiters of the string
        loc = node.content_loc

        Interface::CompletionItem.new(
          label: label,
          text_edit: Interface::TextEdit.new(
            range: range_from_location(loc),
            new_text: label,
          ),
          kind: Constant::CompletionItemKind::FILE,
        )
      end

      #: (String real_name, String incomplete_name, Interface::Range range, Rubydex::Declaration declaration) -> Interface::CompletionItem
      def build_entry_completion(real_name, incomplete_name, range, declaration)
        insertion_text = real_name.dup
        filter_text = real_name.dup

        # When the user explicitly typed `::Foo`, the absolute prefix must be preserved and the suffix-shortening
        # below is skipped — replacing `::Bar` with `Bar` would change which constant resolves. The leading `::` is
        # only present on `incomplete_name` (the user-typed text)
        if incomplete_name.start_with?("::")
          insertion_text.prepend("::") unless insertion_text.start_with?("::")
          filter_text.prepend("::") unless filter_text.start_with?("::")
        else
          shortest = shortest_constant_suffix(real_name)

          if shortest.length < insertion_text.length
            stripped_prefix = real_name.delete_suffix(shortest)
            insertion_text = shortest
            # When the user is typing a more qualified path (e.g. `Foo::B`), keep the filter text qualified so the
            # editor's filter still matches what they typed; otherwise the unqualified suffix is enough
            filter_text = shortest unless incomplete_name.start_with?(stripped_prefix)
          end
        end

        label_details = Interface::CompletionItemLabelDetails.new(description: declaration_file_names(declaration))

        Interface::CompletionItem.new(
          label: real_name,
          label_details: label_details,
          filter_text: filter_text,
          text_edit: Interface::TextEdit.new(
            range: range,
            new_text: insertion_text,
          ),
          kind: declaration.to_lsp_completion_kind,
          data: { fully_qualified_name: declaration.name },
        )
      end

      # Returns the shortest possible name for a constant reference that still resolves to the same target
      #
      #: (String) -> String
      def shortest_constant_suffix(real_name)
        segments = real_name.split("::")
        nesting = @node_context.nesting

        (1..segments.length).each do |suffix_len|
          suffix = segments.last(suffix_len).join("::")
          resolved = @graph.resolve_constant(suffix, nesting)
          return suffix if resolved && resolved.name == real_name
        end

        real_name
      end

      #: (Rubydex::Declaration declaration) -> String
      def declaration_file_names(declaration)
        declaration.definitions.filter_map do |defn|
          uri = URI(defn.location.uri)
          case uri.scheme
          when "untitled"
            uri.opaque
          when "file"
            path = uri.full_path
            File.basename(path) if path
          end
        end.uniq.join(",")
      end
    end
  end
end
