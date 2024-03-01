# typed: strict
# frozen_string_literal: true

module RubyLsp
  module Listeners
    class Completion
      extend T::Sig
      include Requests::Support::Common

      sig do
        params(
          response_builder: ResponseBuilders::CollectionResponseBuilder[Interface::CompletionItem],
          index: RubyIndexer::Index,
          nesting: T::Array[String],
          typechecker_enabled: T::Boolean,
          dispatcher: Prism::Dispatcher,
          uri: URI::Generic,
        ).void
      end
      def initialize(response_builder, index, nesting, typechecker_enabled, dispatcher, uri) # rubocop:disable Metrics/ParameterLists
        @response_builder = response_builder
        @index = index
        @nesting = nesting
        @typechecker_enabled = typechecker_enabled
        @uri = uri

        dispatcher.register(
          self,
          :on_constant_path_node_enter,
          :on_constant_read_node_enter,
          :on_call_node_enter,
        )
      end

      # Handle completion on regular constant references (e.g. `Bar`)
      sig { params(node: Prism::ConstantReadNode).void }
      def on_constant_read_node_enter(node)
        return if DependencyDetector.instance.typechecker

        name = constant_name(node)
        return if name.nil?

        candidates = @index.prefix_search(name, @nesting)
        candidates.each do |entries|
          complete_name = T.must(entries.first).name
          @response_builder << build_entry_completion(
            complete_name,
            name,
            node,
            entries,
            top_level?(complete_name),
          )
        end
      end

      # Handle completion on namespaced constant references (e.g. `Foo::Bar`)
      sig { params(node: Prism::ConstantPathNode).void }
      def on_constant_path_node_enter(node)
        return if DependencyDetector.instance.typechecker

        name = constant_name(node)
        return if name.nil?

        top_level_reference = if name.start_with?("::")
          name = name.delete_prefix("::")
          true
        else
          false
        end

        # If we're trying to provide completion for an aliased namespace, we need to first discover it's real name in
        # order to find which possible constants match the desired search
        *namespace, incomplete_name = name.split("::")
        aliased_namespace = T.must(namespace).join("::")
        namespace_entries = @index.resolve(aliased_namespace, @nesting)
        return unless namespace_entries

        real_namespace = @index.follow_aliased_namespace(T.must(namespace_entries.first).name)

        candidates = @index.prefix_search("#{real_namespace}::#{incomplete_name}", top_level_reference ? [] : @nesting)
        candidates.each do |entries|
          # The only time we may have a private constant reference from outside of the namespace is if we're dealing
          # with ConstantPath and the entry name doesn't start with the current nesting
          first_entry = T.must(entries.first)
          next if first_entry.visibility == :private && !first_entry.name.start_with?("#{@nesting}::")

          constant_name = T.must(first_entry.name.split("::").last)

          full_name = aliased_namespace.empty? ? constant_name : "#{aliased_namespace}::#{constant_name}"

          @response_builder << build_entry_completion(
            full_name,
            name,
            node,
            entries,
            top_level_reference || top_level?(T.must(entries.first).name),
          )
        end
      end

      sig { params(node: Prism::CallNode).void }
      def on_call_node_enter(node)
        name = node.message
        return unless name

        case name
        when "require"
          complete_require(node)
        when "require_relative"
          complete_require_relative(node)
        else
          complete_self_receiver_method(node, name) if !@typechecker_enabled && self_receiver?(node)
        end
      end

      private

      sig { params(node: Prism::CallNode).void }
      def complete_require(node)
        arguments_node = node.arguments
        return unless arguments_node

        path_node_to_complete = arguments_node.arguments.first

        return unless path_node_to_complete.is_a?(Prism::StringNode)

        @index.search_require_paths(path_node_to_complete.content).map!(&:require_path).sort!.each do |path|
          @response_builder << build_completion(T.must(path), path_node_to_complete)
        end
      end

      sig { params(node: Prism::CallNode).void }
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
      end

      sig { params(node: Prism::CallNode, name: String).void }
      def complete_self_receiver_method(node, name)
        receiver_entries = @index[@nesting.join("::")]
        return unless receiver_entries

        receiver = T.must(receiver_entries.first)

        @index.prefix_search(name).each do |entries|
          entry = entries.find { |e| e.is_a?(RubyIndexer::Entry::Member) && e.owner&.name == receiver.name }
          next unless entry

          @response_builder << build_method_completion(T.cast(entry, RubyIndexer::Entry::Member), node)
        end
      end

      sig do
        params(
          entry: RubyIndexer::Entry::Member,
          node: Prism::CallNode,
        ).returns(Interface::CompletionItem)
      end
      def build_method_completion(entry, node)
        name = entry.name

        Interface::CompletionItem.new(
          label: name,
          filter_text: name,
          text_edit: Interface::TextEdit.new(range: range_from_location(T.must(node.message_loc)), new_text: name),
          kind: Constant::CompletionItemKind::METHOD,
          label_details: Interface::CompletionItemLabelDetails.new(
            detail: "(#{entry.parameters.map(&:decorated_name).join(", ")})",
            description: entry.file_name,
          ),
          documentation: Interface::MarkupContent.new(
            kind: "markdown",
            value: markdown_from_index_entries(name, entry),
          ),
        )
      end

      sig { params(label: String, node: Prism::StringNode).returns(Interface::CompletionItem) }
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

      sig do
        params(
          real_name: String,
          incomplete_name: String,
          node: Prism::Node,
          entries: T::Array[RubyIndexer::Entry],
          top_level: T::Boolean,
        ).returns(Interface::CompletionItem)
      end
      def build_entry_completion(real_name, incomplete_name, node, entries, top_level)
        first_entry = T.must(entries.first)
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
        @nesting.each do |namespace|
          prefix = "#{namespace}::"
          shortened_name = insertion_text.delete_prefix(prefix)

          # If a different entry exists for the shortened name, then there's a conflict and we should not shorten it
          conflict_name = "#{@nesting.join("::")}::#{shortened_name}"
          break if real_name != conflict_name && @index[conflict_name]

          insertion_text = shortened_name

          # If the user is typing a fully qualified name `Foo::Bar::Baz`, then we should not use the short name (e.g.:
          # `Baz`) as filtering. So we only shorten the filter text if the user is not including the namespaces in their
          # typing
          filter_text.delete_prefix!(prefix) unless incomplete_name.start_with?(prefix)
        end

        # When using a top level constant reference (e.g.: `::Bar`), the editor includes the `::` as part of the filter.
        # For these top level references, we need to include the `::` as part of the filter text or else it won't match
        # the right entries in the index
        Interface::CompletionItem.new(
          label: real_name,
          filter_text: filter_text,
          text_edit: Interface::TextEdit.new(
            range: range_from_node(node),
            new_text: insertion_text,
          ),
          kind: kind,
          label_details: Interface::CompletionItemLabelDetails.new(
            description: entries.map(&:file_name).join(","),
          ),
          documentation: Interface::MarkupContent.new(
            kind: "markdown",
            value: markdown_from_index_entries(real_name, entries),
          ),
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
      sig { params(entry_name: String).returns(T::Boolean) }
      def top_level?(entry_name)
        @nesting.length.downto(0).each do |i|
          prefix = T.must(@nesting[0...i]).join("::")
          full_name = prefix.empty? ? entry_name : "#{prefix}::#{entry_name}"
          next if full_name == entry_name

          return true if @index[full_name]
        end

        false
      end
    end
  end
end
