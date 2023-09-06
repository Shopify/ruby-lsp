# typed: strict
# frozen_string_literal: true

module RubyLsp
  module Requests
    # ![Path completion demo](../../path_completion.gif)
    #
    # The [completion](https://microsoft.github.io/language-server-protocol/specification#textDocument_completion)
    # request looks up Ruby files in the $LOAD_PATH to suggest path completion inside `require` statements.
    #
    # # Example
    #
    # ```ruby
    # require "ruby_lsp/requests" # --> completion: suggests `base_request`, `code_actions`, ...
    # ```
    class PathCompletion < Listener
      extend T::Sig
      extend T::Generic

      ResponseType = type_member { { fixed: T::Array[Interface::CompletionItem] } }

      sig { override.returns(ResponseType) }
      attr_reader :response

      sig { params(index: RubyIndexer::Index, emitter: EventEmitter, message_queue: Thread::Queue).void }
      def initialize(index, emitter, message_queue)
        super(emitter, message_queue)
        @response = T.let([], ResponseType)
        @index = index

        emitter.register(self, :on_string)
      end

      sig { params(node: YARP::StringNode).void }
      def on_string(node)
        @index.search_require_paths(node.content_loc.slice).sort!.each do |path|
          @response << build_completion(path, node)
        end
      end

      private

      sig { returns(T::Array[String]) }
      def collect_load_path_files
        $LOAD_PATH.flat_map do |p|
          Dir.glob("**/*.rb", base: p)
        end.each do |result|
          entry = result.delete_suffix!(".rb")
          @tree.insert(entry, entry)
        end
      end

      sig { params(label: String, node: YARP::StringNode).returns(Interface::CompletionItem) }
      def build_completion(label, node)
        Interface::CompletionItem.new(
          label: label,
          text_edit: Interface::TextEdit.new(
            range: range_from_location(node.content_loc),
            new_text: label,
          ),
          kind: Constant::CompletionItemKind::REFERENCE,
        )
      end
    end
  end
end
