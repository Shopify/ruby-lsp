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
          YARP::ClassNode,
          YARP::ModuleNode,
          YARP::ConstantWriteNode,
        ],
        T::Array[T.class_of(YARP::Node)],
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
        emitter.register(self, :on_class, :on_module, :on_constant_write)
      end

      # Merges responses from other hover listeners
      sig { override.params(other: Listener[ResponseType]).returns(T.self_type) }
      def merge_response!(other)
        other_response = other.response
        return self unless other_response

        if @response.nil?
          @response = other.response
        else
          @response.contents.value << "\n\n" << other_response.contents.value
        end

        self
      end

      sig { params(node: YARP::ClassNode).void }
      def on_class(node)
        return if DependencyDetector::HAS_TYPECHECKER

        generate_hover(node.name, node.constant_path.location)
      end

      sig { params(node: YARP::ModuleNode).void }
      def on_module(node)
        return if DependencyDetector::HAS_TYPECHECKER

        generate_hover(node.name, node.constant_path.location)
      end

      sig { params(node: YARP::ConstantWriteNode).void }
      def on_constant_write(node)
        return if DependencyDetector::HAS_TYPECHECKER

        generate_hover(node.name, node.name_loc)
      end

      private

      sig { params(name: String, location: YARP::Location).void }
      def generate_hover(name, location)
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
        @response = Interface::Hover.new(range: range_from_location(location), contents: contents)
      end
    end
  end
end
