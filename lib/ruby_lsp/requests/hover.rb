# typed: strict
# frozen_string_literal: true

module RubyLsp
  module Requests
    # ![Hover demo](../../hover.gif)
    #
    # The [hover request](https://microsoft.github.io/language-server-protocol/specification#textDocument_hover)
    # displays the documentation for the symbol currently under the cursor.
    #
    # # Example
    #
    # ```ruby
    # String # -> Hovering over the class reference will show all declaration locations and the documentation
    # ```
    class Hover < Listener
      extend T::Sig
      extend T::Generic

      ResponseType = type_member { { fixed: T.nilable(Interface::Hover) } }

      ALLOWED_TARGETS = T.let(
        [
          SyntaxTree::Const,
          SyntaxTree::Command,
          SyntaxTree::CallNode,
          SyntaxTree::ConstPathRef,
        ],
        T::Array[T.class_of(SyntaxTree::Node)],
      )

      sig { override.returns(ResponseType) }
      attr_reader :response

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

        @nesting = nesting
        @index = index
        @external_listeners.concat(
          Extension.extensions.filter_map { |ext| ext.create_hover_listener(emitter, message_queue) },
        )
        @response = T.let(nil, ResponseType)
        emitter.register(self, :on_const_path_ref, :on_const)
      end

      # Merges responses from other hover listeners
      sig { override.params(other: Listener[ResponseType]).returns(T.self_type) }
      def merge_response!(other)
        other_response = other.response
        return self unless other_response

        if @response.nil?
          @response = other.response
        else
          @response.contents.value << other_response.contents.value << "\n\n"
        end

        self
      end

      sig { params(node: SyntaxTree::ConstPathRef).void }
      def on_const_path_ref(node)
        return if DependencyDetector::HAS_TYPECHECKER

        name = full_constant_name(node)
        generate_hover(name, node)
      end

      sig { params(node: SyntaxTree::Const).void }
      def on_const(node)
        return if DependencyDetector::HAS_TYPECHECKER

        generate_hover(node.value, node)
      end

      private

      sig { params(name: String, node: SyntaxTree::Node).void }
      def generate_hover(name, node)
        entries = @index.resolve(name, @nesting)
        return unless entries

        title = +"```ruby\n#{name}\n```"
        definitions = []
        content = +""
        entries.each do |entry|
          loc = entry.location

          # We always handle locations as zero based. However, for file links in Markdown we need them to be one based,
          # which is why instead of the usual subtraction of 1 to line numbers, we are actually adding 1 to columns. The
          # format for VS Code file URIs is `file:///path/to/file.rb#Lstart_line,start_column-end_line,end_column`
          uri = URI::Generic.from_path(
            path: entry.file_path,
            fragment: "L#{loc.start_line},#{loc.start_column + 1}-#{loc.end_line},#{loc.end_column + 1}",
          )

          definitions << "[#{entry.file_name}](#{uri})"
          content << "\n\n#{entry.comments.join("\n")}" unless entry.comments.empty?
        end

        contents = Interface::MarkupContent.new(
          kind: "markdown",
          value: "#{title}\n\n**Definitions**: #{definitions.join(" | ")}\n\n#{content}",
        )
        @response = Interface::Hover.new(range: range_from_syntax_tree_node(node), contents: contents)
      end
    end
  end
end
