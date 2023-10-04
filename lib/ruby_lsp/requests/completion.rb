# typed: strict
# frozen_string_literal: true

module RubyLsp
  module Requests
    # ![Completion demo](../../completion.gif)
    #
    # The [completion](https://microsoft.github.io/language-server-protocol/specification#textDocument_completion)
    # suggests possible completions according to what the developer is typing. Currently, completion is support for
    # - require paths
    # - classes, modules and constant names
    #
    # # Example
    #
    # ```ruby
    # require "ruby_lsp/requests" # --> completion: suggests `base_request`, `code_actions`, ...
    #
    # RubyLsp::Requests:: # --> completion: suggests `Completion`, `Hover`, ...
    # ```
    class Completion < Listener
      extend T::Sig
      extend T::Generic

      ResponseType = type_member { { fixed: T::Array[Interface::CompletionItem] } }

      sig { override.returns(ResponseType) }
      attr_reader :_response

      sig do
        params(
          index: RubyIndexer::Index,
          nesting: T::Array[String],
          emitter: EventEmitter,
          message_queue: Thread::Queue,
        ).void
      end
      def initialize(index, nesting, emitter, message_queue)
        super(emitter, message_queue)
        @_response = T.let([], ResponseType)
        @index = index
        @nesting = nesting

        emitter.register(self, :on_string, :on_constant_path, :on_constant_read)
      end

      sig { params(node: YARP::StringNode).void }
      def on_string(node)
        @index.search_require_paths(node.content).map!(&:require_path).sort!.each do |path|
          @_response << build_completion(T.must(path), node)
        end
      end

      # Handle completion on regular constant references (e.g. `Bar`)
      sig { params(node: YARP::ConstantReadNode).void }
      def on_constant_read(node)
        return if DependencyDetector.instance.typechecker

        name = node.slice
        candidates = @index.prefix_search(name, @nesting)
        candidates.each do |entries|
          complete_name = T.must(entries.first).name
          @_response << build_entry_completion(complete_name, node, entries, top_level?(complete_name, candidates))
        end
      end

      # Handle completion on namespaced constant references (e.g. `Foo::Bar`)
      sig { params(node: YARP::ConstantPathNode).void }
      def on_constant_path(node)
        return if DependencyDetector.instance.typechecker

        name = node.slice

        top_level_reference = if name.start_with?("::")
          name = name.delete_prefix("::")
          true
        else
          false
        end

        # If we're trying to provide completion for an aliased namespace, we need to first discover it's real name in
        # order to find which possible constants match the desired search
        *namespace, incomplete_name = name.split("::")
        aliased_namespace = namespace.join("::")
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

          @_response << build_entry_completion(
            full_name,
            node,
            entries,
            top_level_reference || top_level?(T.must(entries.first).name, candidates),
          )
        end
      end

      private

      sig { params(label: String, node: YARP::StringNode).returns(Interface::CompletionItem) }
      def build_completion(label, node)
        Interface::CompletionItem.new(
          label: label,
          text_edit: Interface::TextEdit.new(
            range: range_from_node(node),
            new_text: label,
          ),
          kind: Constant::CompletionItemKind::REFERENCE,
        )
      end

      sig do
        params(
          name: String,
          node: YARP::Node,
          entries: T::Array[RubyIndexer::Index::Entry],
          top_level: T::Boolean,
        ).returns(Interface::CompletionItem)
      end
      def build_entry_completion(name, node, entries, top_level)
        first_entry = T.must(entries.first)
        kind = case first_entry
        when RubyIndexer::Index::Entry::Class
          Constant::CompletionItemKind::CLASS
        when RubyIndexer::Index::Entry::Module
          Constant::CompletionItemKind::MODULE
        when RubyIndexer::Index::Entry::Constant
          Constant::CompletionItemKind::CONSTANT
        else
          Constant::CompletionItemKind::REFERENCE
        end

        insertion_text = name.dup

        # If we have two entries with the same name inside the current namespace and the user selects the top level
        # option, we have to ensure it's prefixed with `::` or else we're completing the wrong constant. For example:
        # If we have the index with ["Foo::Bar", "Bar"], and we're providing suggestions for `B` inside a `Foo` module,
        # then selecting the `Foo::Bar` option needs to complete to `Bar` and selecting the top level `Bar` option needs
        # to complete to `::Bar`.
        insertion_text.prepend("::") if top_level

        # If the user is searching for a constant inside the current namespace, then we prefer completing the short name
        # of that constant. E.g.:
        #
        # module Foo
        #  class Bar
        #  end
        #
        #  Foo::B # --> completion inserts `Bar` instead of `Foo::Bar`
        # end
        @nesting.each { |namespace| insertion_text.delete_prefix!("#{namespace}::") }

        # When using a top level constant reference (e.g.: `::Bar`), the editor includes the `::` as part of the filter.
        # For these top level references, we need to include the `::` as part of the filter text or else it won't match
        # the right entries in the index
        Interface::CompletionItem.new(
          label: name,
          filter_text: top_level ? "::#{name}" : name,
          text_edit: Interface::TextEdit.new(
            range: range_from_node(node),
            new_text: insertion_text,
          ),
          kind: kind,
          label_details: Interface::CompletionItemLabelDetails.new(
            description: entries.map(&:file_name).join(","),
          ),
          documentation: markdown_from_index_entries(name, entries),
        )
      end

      # Check if the `entry_name` has potential conflicts in `candidates`, so that we use a top level reference instead
      # of a short name
      sig { params(entry_name: String, candidates: T::Array[T::Array[RubyIndexer::Index::Entry]]).returns(T::Boolean) }
      def top_level?(entry_name, candidates)
        candidates.any? { |entries| T.must(entries.first).name == "#{@nesting.join("::")}::#{entry_name}" }
      end
    end
  end
end
