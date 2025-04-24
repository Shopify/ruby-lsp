# typed: strict
# frozen_string_literal: true

module RubyLsp
  module Listeners
    class Completion
      include Requests::Support::Common

      KEYWORDS = [
        "alias",
        "and",
        "begin",
        "BEGIN",
        "break",
        "case",
        "class",
        "def",
        "defined?",
        "do",
        "else",
        "elsif",
        "end",
        "END",
        "ensure",
        "false",
        "for",
        "if",
        "in",
        "module",
        "next",
        "nil",
        "not",
        "or",
        "redo",
        "rescue",
        "retry",
        "return",
        "self",
        "super",
        "then",
        "true",
        "undef",
        "unless",
        "until",
        "when",
        "while",
        "yield",
        "__ENCODING__",
        "__FILE__",
        "__LINE__",
      ].freeze

      #: (ResponseBuilders::CollectionResponseBuilder[Interface::CompletionItem] response_builder, GlobalState global_state, NodeContext node_context, RubyDocument::SorbetLevel sorbet_level, Prism::Dispatcher dispatcher, URI::Generic uri, String? trigger_character) -> void
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
        @index = global_state.index #: RubyIndexer::Index
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
        return if @sorbet_level != RubyDocument::SorbetLevel::Ignore

        name = RubyIndexer::Index.constant_name(node)
        return if name.nil?

        range = range_from_location(node.location)
        candidates = @index.constant_completion_candidates(name, @node_context.nesting)
        candidates.each do |entries|
          complete_name = entries.first #: as !nil
            .name
          @response_builder << build_entry_completion(
            complete_name,
            name,
            range,
            entries,
            top_level?(complete_name),
          )
        end
      end

      # Handle completion on namespaced constant references (e.g. `Foo::Bar`)
      #: (Prism::ConstantPathNode node) -> void
      def on_constant_path_node_enter(node)
        # The only scenario where Sorbet doesn't provide constant completion is on ignored files. Even if the file has
        # no sigil, Sorbet will still provide completion for constants
        return if @sorbet_level != RubyDocument::SorbetLevel::Ignore

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
        if @sorbet_level == RubyDocument::SorbetLevel::Ignore
          receiver = node.receiver

          # When writing `Foo::`, the AST assigns a method call node (because you can use that syntax to invoke
          # singleton methods). However, in addition to providing method completion, we also need to show possible
          # constant completions
          if (receiver.is_a?(Prism::ConstantReadNode) || receiver.is_a?(Prism::ConstantPathNode)) &&
              node.call_operator == "::"

            name = RubyIndexer::Index.constant_name(receiver)

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
          complete_methods(node, name)
        end
      end

      #: (Prism::GlobalVariableAndWriteNode node) -> void
      def on_global_variable_and_write_node_enter(node)
        handle_global_variable_completion(node.name.to_s, node.name_loc)
      end

      #: (Prism::GlobalVariableOperatorWriteNode node) -> void
      def on_global_variable_operator_write_node_enter(node)
        handle_global_variable_completion(node.name.to_s, node.name_loc)
      end

      #: (Prism::GlobalVariableOrWriteNode node) -> void
      def on_global_variable_or_write_node_enter(node)
        handle_global_variable_completion(node.name.to_s, node.name_loc)
      end

      #: (Prism::GlobalVariableReadNode node) -> void
      def on_global_variable_read_node_enter(node)
        handle_global_variable_completion(node.name.to_s, node.location)
      end

      #: (Prism::GlobalVariableTargetNode node) -> void
      def on_global_variable_target_node_enter(node)
        handle_global_variable_completion(node.name.to_s, node.location)
      end

      #: (Prism::GlobalVariableWriteNode node) -> void
      def on_global_variable_write_node_enter(node)
        handle_global_variable_completion(node.name.to_s, node.name_loc)
      end

      #: (Prism::InstanceVariableReadNode node) -> void
      def on_instance_variable_read_node_enter(node)
        handle_instance_variable_completion(node.name.to_s, node.location)
      end

      #: (Prism::InstanceVariableWriteNode node) -> void
      def on_instance_variable_write_node_enter(node)
        handle_instance_variable_completion(node.name.to_s, node.name_loc)
      end

      #: (Prism::InstanceVariableAndWriteNode node) -> void
      def on_instance_variable_and_write_node_enter(node)
        handle_instance_variable_completion(node.name.to_s, node.name_loc)
      end

      #: (Prism::InstanceVariableOperatorWriteNode node) -> void
      def on_instance_variable_operator_write_node_enter(node)
        handle_instance_variable_completion(node.name.to_s, node.name_loc)
      end

      #: (Prism::InstanceVariableOrWriteNode node) -> void
      def on_instance_variable_or_write_node_enter(node)
        handle_instance_variable_completion(node.name.to_s, node.name_loc)
      end

      #: (Prism::InstanceVariableTargetNode node) -> void
      def on_instance_variable_target_node_enter(node)
        handle_instance_variable_completion(node.name.to_s, node.location)
      end

      #: (Prism::ClassVariableAndWriteNode node) -> void
      def on_class_variable_and_write_node_enter(node)
        handle_class_variable_completion(node.name.to_s, node.name_loc)
      end

      #: (Prism::ClassVariableOperatorWriteNode node) -> void
      def on_class_variable_operator_write_node_enter(node)
        handle_class_variable_completion(node.name.to_s, node.name_loc)
      end

      #: (Prism::ClassVariableOrWriteNode node) -> void
      def on_class_variable_or_write_node_enter(node)
        handle_class_variable_completion(node.name.to_s, node.name_loc)
      end

      #: (Prism::ClassVariableTargetNode node) -> void
      def on_class_variable_target_node_enter(node)
        handle_class_variable_completion(node.name.to_s, node.location)
      end

      #: (Prism::ClassVariableReadNode node) -> void
      def on_class_variable_read_node_enter(node)
        handle_class_variable_completion(node.name.to_s, node.location)
      end

      #: (Prism::ClassVariableWriteNode node) -> void
      def on_class_variable_write_node_enter(node)
        handle_class_variable_completion(node.name.to_s, node.name_loc)
      end

      private

      #: (String name, Interface::Range range) -> void
      def constant_path_completion(name, range)
        top_level_reference = if name.start_with?("::")
          name = name.delete_prefix("::")
          true
        else
          false
        end

        # If we're trying to provide completion for an aliased namespace, we need to first discover it's real name in
        # order to find which possible constants match the desired search
        aliased_namespace = if name.end_with?("::")
          name.delete_suffix("::")
        else
          *namespace, incomplete_name = name.split("::")
          namespace.join("::")
        end

        nesting = @node_context.nesting
        namespace_entries = @index.resolve(aliased_namespace, nesting)
        return unless namespace_entries

        namespace_name = namespace_entries.first #: as !nil
          .name
        real_namespace = @index.follow_aliased_namespace(namespace_name)

        candidates = @index.constant_completion_candidates(
          "#{real_namespace}::#{incomplete_name}",
          top_level_reference ? [] : nesting,
        )
        candidates.each do |entries|
          # The only time we may have a private constant reference from outside of the namespace is if we're dealing
          # with ConstantPath and the entry name doesn't start with the current nesting
          first_entry = entries.first #: as !nil
          next if first_entry.private? && !first_entry.name.start_with?("#{nesting}::")

          entry_name = first_entry.name
          full_name = if aliased_namespace != real_namespace
            constant_name = entry_name.delete_prefix("#{real_namespace}::")
            aliased_namespace.empty? ? constant_name : "#{aliased_namespace}::#{constant_name}"
          elsif !entry_name.start_with?(aliased_namespace)
            *_, short_name = entry_name.split("::")
            "#{aliased_namespace}::#{short_name}"
          else
            entry_name
          end

          @response_builder << build_entry_completion(
            full_name,
            name,
            range,
            entries,
            top_level_reference || top_level?(first_entry.name),
          )
        end
      end

      #: (String name, Prism::Location location) -> void
      def handle_global_variable_completion(name, location)
        candidates = @index.prefix_search(name)

        return if candidates.none?

        range = range_from_location(location)

        candidates.flatten.uniq(&:name).each do |entry|
          entry_name = entry.name

          @response_builder << Interface::CompletionItem.new(
            label: entry_name,
            filter_text: entry_name,
            label_details: Interface::CompletionItemLabelDetails.new(
              description: entry.file_name,
            ),
            text_edit: Interface::TextEdit.new(range: range, new_text: entry_name),
            kind: Constant::CompletionItemKind::VARIABLE,
          )
        end
      end

      #: (String name, Prism::Location location) -> void
      def handle_class_variable_completion(name, location)
        type = @type_inferrer.infer_receiver_type(@node_context)
        return unless type

        range = range_from_location(location)

        @index.class_variable_completion_candidates(name, type.name).each do |entry|
          variable_name = entry.name

          label_details = Interface::CompletionItemLabelDetails.new(
            description: entry.file_name,
          )

          @response_builder << Interface::CompletionItem.new(
            label: variable_name,
            label_details: label_details,
            text_edit: Interface::TextEdit.new(
              range: range,
              new_text: variable_name,
            ),
            kind: Constant::CompletionItemKind::FIELD,
            data: {
              owner_name: entry.owner&.name,
            },
          )
        end
      rescue RubyIndexer::Index::NonExistingNamespaceError
        # If by any chance we haven't indexed the owner, then there's no way to find the right declaration
      end

      #: (String name, Prism::Location location) -> void
      def handle_instance_variable_completion(name, location)
        # Sorbet enforces that all instance variables be declared on typed strict or higher, which means it will be able
        # to provide all features for them
        return if @sorbet_level == RubyDocument::SorbetLevel::Strict

        type = @type_inferrer.infer_receiver_type(@node_context)
        return unless type

        range = range_from_location(location)
        @index.instance_variable_completion_candidates(name, type.name).each do |entry|
          variable_name = entry.name

          label_details = Interface::CompletionItemLabelDetails.new(
            description: entry.file_name,
          )

          @response_builder << Interface::CompletionItem.new(
            label: variable_name,
            label_details: label_details,
            text_edit: Interface::TextEdit.new(
              range: range,
              new_text: variable_name,
            ),
            kind: Constant::CompletionItemKind::FIELD,
            data: {
              owner_name: entry.owner&.name,
            },
          )
        end
      rescue RubyIndexer::Index::NonExistingNamespaceError
        # If by any chance we haven't indexed the owner, then there's no way to find the right declaration
      end

      #: (Prism::CallNode node) -> void
      def complete_require(node)
        arguments_node = node.arguments
        return unless arguments_node

        path_node_to_complete = arguments_node.arguments.first

        return unless path_node_to_complete.is_a?(Prism::StringNode)

        matched_uris = @index.search_require_paths(path_node_to_complete.content)

        matched_uris.map!(&:require_path).sort!.each do |path|
          @response_builder << build_completion(
            path, #: as !nil
            path_node_to_complete,
          )
        end
      end

      #: (Prism::CallNode node) -> void
      def complete_require_relative(node)
        arguments_node = node.arguments
        return unless arguments_node

        path_node_to_complete = arguments_node.arguments.first

        return unless path_node_to_complete.is_a?(Prism::StringNode)

        origin_dir = Pathname.new(@uri.to_standardized_path).dirname

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

      #: (Prism::CallNode node, String name) -> void
      def complete_methods(node, name)
        # If the node has a receiver, then we don't need to provide local nor keyword completions. Sorbet can provide
        # local and keyword completion for any file with a Sorbet level of true or higher
        if !sorbet_level_true_or_higher?(@sorbet_level) && !node.receiver
          add_local_completions(node, name)
          add_keyword_completions(node, name)
        end

        # Sorbet can provide completion for methods invoked on self on typed true or higher files
        return if sorbet_level_true_or_higher?(@sorbet_level) && self_receiver?(node)

        type = @type_inferrer.infer_receiver_type(@node_context)
        return unless type

        # When the trigger character is a dot, Prism matches the name of the call node to whatever is next in the source
        # code, leading to us searching for the wrong name. What we want to do instead is show every available method
        # when dot is pressed
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
        external_references = @node_context.fully_qualified_name != type.name

        @index.method_completion_candidates(method_name, type.name).each do |entry|
          next if entry.visibility != RubyIndexer::Entry::Visibility::PUBLIC && external_references

          entry_name = entry.name
          owner_name = entry.owner&.name

          label_details = Interface::CompletionItemLabelDetails.new(
            description: entry.file_name,
            detail: entry.decorated_parameters,
          )
          @response_builder << Interface::CompletionItem.new(
            label: entry_name,
            filter_text: entry_name,
            label_details: label_details,
            text_edit: Interface::TextEdit.new(range: range, new_text: entry_name),
            kind: Constant::CompletionItemKind::METHOD,
            data: {
              owner_name: owner_name,
              guessed_type: guessed_type,
            },
          )
        end
      rescue RubyIndexer::Index::NonExistingNamespaceError
        # We have not indexed this namespace, so we can't provide any completions
      end

      #: (Prism::CallNode node, String name) -> void
      def add_local_completions(node, name)
        range = range_from_location(
          node.message_loc, #: as !nil
        )

        @node_context.locals_for_scope.each do |local|
          local_name = local.to_s
          next unless local_name.start_with?(name)

          @response_builder << Interface::CompletionItem.new(
            label: local_name,
            filter_text: local_name,
            text_edit: Interface::TextEdit.new(range: range, new_text: local_name),
            kind: Constant::CompletionItemKind::VARIABLE,
            data: {
              skip_resolve: true,
            },
          )
        end
      end

      #: (Prism::CallNode node, String name) -> void
      def add_keyword_completions(node, name)
        range = range_from_location(
          node.message_loc, #: as !nil
        )

        KEYWORDS.each do |keyword|
          next unless keyword.start_with?(name)

          @response_builder << Interface::CompletionItem.new(
            label: keyword,
            text_edit: Interface::TextEdit.new(range: range, new_text: keyword),
            kind: Constant::CompletionItemKind::KEYWORD,
            data: {
              keyword: true,
            },
          )
        end
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

      #: (String real_name, String incomplete_name, Interface::Range range, Array[RubyIndexer::Entry] entries, bool top_level) -> Interface::CompletionItem
      def build_entry_completion(real_name, incomplete_name, range, entries, top_level)
        first_entry = entries.first #: as !nil
        kind = case first_entry
        when RubyIndexer::Entry::Class
          Constant::CompletionItemKind::CLASS
        when RubyIndexer::Entry::Module
          Constant::CompletionItemKind::MODULE
        when RubyIndexer::Entry::Constant
          Constant::CompletionItemKind::CONSTANT
        else
          Constant::CompletionItemKind::REFERENCE
        end

        insertion_text = real_name.dup
        filter_text = real_name.dup

        # If we have two entries with the same name inside the current namespace and the user selects the top level
        # option, we have to ensure it's prefixed with `::` or else we're completing the wrong constant. For example:
        # If we have the index with ["Foo::Bar", "Bar"], and we're providing suggestions for `B` inside a `Foo` module,
        # then selecting the `Foo::Bar` option needs to complete to `Bar` and selecting the top level `Bar` option needs
        # to complete to `::Bar`.
        if top_level
          insertion_text.prepend("::")
          filter_text.prepend("::")
        end

        # If the user is searching for a constant inside the current namespace, then we prefer completing the short name
        # of that constant. E.g.:
        #
        # module Foo
        #  class Bar
        #  end
        #
        #  Foo::B # --> completion inserts `Bar` instead of `Foo::Bar`
        # end
        nesting = @node_context.nesting
        unless @node_context.fully_qualified_name.start_with?(incomplete_name)
          nesting.each do |namespace|
            prefix = "#{namespace}::"
            shortened_name = insertion_text.delete_prefix(prefix)

            # If a different entry exists for the shortened name, then there's a conflict and we should not shorten it
            conflict_name = "#{@node_context.fully_qualified_name}::#{shortened_name}"
            break if real_name != conflict_name && @index[conflict_name]

            insertion_text = shortened_name

            # If the user is typing a fully qualified name `Foo::Bar::Baz`, then we should not use the short name (e.g.:
            # `Baz`) as filtering. So we only shorten the filter text if the user is not including the namespaces in
            # their typing
            filter_text.delete_prefix!(prefix) unless incomplete_name.start_with?(prefix)
          end
        end

        # When using a top level constant reference (e.g.: `::Bar`), the editor includes the `::` as part of the filter.
        # For these top level references, we need to include the `::` as part of the filter text or else it won't match
        # the right entries in the index

        label_details = Interface::CompletionItemLabelDetails.new(
          description: entries.map(&:file_name).join(","),
        )

        Interface::CompletionItem.new(
          label: real_name,
          label_details: label_details,
          filter_text: filter_text,
          text_edit: Interface::TextEdit.new(
            range: range,
            new_text: insertion_text,
          ),
          kind: kind,
        )
      end

      # Check if there are any conflicting names for `entry_name`, which would require us to use a top level reference.
      # For example:
      #
      # ```ruby
      # class Bar; end
      #
      # module Foo
      #   class Bar; end
      #
      #   # in this case, the completion for `Bar` conflicts with `Foo::Bar`, so we can't suggest `Bar` as the
      #   # completion, but instead need to suggest `::Bar`
      #   B
      # end
      # ```
      #: (String entry_name) -> bool
      def top_level?(entry_name)
        nesting = @node_context.nesting
        nesting.length.downto(0) do |i|
          prefix = nesting[0...i] #: as !nil
            .join("::")
          full_name = prefix.empty? ? entry_name : "#{prefix}::#{entry_name}"
          next if full_name == entry_name

          return true if @index[full_name]
        end

        false
      end
    end
  end
end
