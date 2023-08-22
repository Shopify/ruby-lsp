# typed: strict
# frozen_string_literal: true

module RubyLsp
  module Requests
    # ![Hover demo](../../rails_document_link_hover.gif)
    #
    # The [hover request](https://microsoft.github.io/language-server-protocol/specification#textDocument_hover)
    # renders a clickable link to the code's official documentation.
    # It currently only supports Rails' documentation: when hovering over Rails DSLs/constants under certain paths,
    # like `before_save :callback` in `models/post.rb`, it generates a link to `before_save`'s API documentation.
    #
    # # Example
    #
    # ```ruby
    # class Post < ApplicationRecord
    #   before_save :do_something # when hovering on before_save, the link will be rendered
    # end
    # ```
    class Hover < Listener
      extend T::Sig
      extend T::Generic

      ResponseType = type_member { { fixed: T.nilable(Interface::Hover) } }

      ALLOWED_TARGETS = T.let(
        [
          YARP::CallNode,
          YARP::ConstantPathNode,
        ],
        T::Array[T.class_of(YARP::Node)],
      )

      sig { override.returns(ResponseType) }
      attr_reader :response

      sig { params(emitter: EventEmitter, message_queue: Thread::Queue).void }
      def initialize(emitter, message_queue)
        super

        @external_listeners.concat(
          Extension.extensions.filter_map { |ext| ext.create_hover_listener(emitter, message_queue) },
        )
        @response = T.let(nil, ResponseType)
        emitter.register(self, :on_constant_path, :on_call)
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

      sig { params(node: YARP::ConstantPathNode).void }
      def on_constant_path(node)
        @response = generate_rails_document_link_hover(node.location.slice, node.location)
      end

      sig { params(node: YARP::CallNode).void }
      def on_call(node)
        message = node.message
        return if message.is_a?(Symbol)

        @response = generate_rails_document_link_hover(message, node.message_loc)
      end

      private

      sig { params(name: String, location: YARP::Location).returns(T.nilable(Interface::Hover)) }
      def generate_rails_document_link_hover(name, location)
        urls = Support::RailsDocumentClient.generate_rails_document_urls(name)
        return if urls.empty?

        contents = Interface::MarkupContent.new(kind: "markdown", value: urls.join("\n\n"))
        Interface::Hover.new(range: range_from_location(location), contents: contents)
      end
    end
  end
end
