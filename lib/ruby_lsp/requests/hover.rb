# typed: strict
# frozen_string_literal: true

module RubyLsp
  module Requests
    # ![Hover demo](../../misc/rails_document_link_hover.gif)
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
          SyntaxTree::Command,
          SyntaxTree::CallNode,
          SyntaxTree::ConstPathRef,
        ],
        T::Array[T.class_of(SyntaxTree::Node)],
      )

      sig { override.returns(ResponseType) }
      attr_reader :response

      sig { void }
      def initialize
        @response = T.let(nil, ResponseType)
        super()
      end

      # Merges responses from other hover listeners
      sig { params(other: Listener[ResponseType]).returns(T.self_type) }
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

      listener_events do
        sig { params(node: SyntaxTree::Command).void }
        def on_command(node)
          message = node.message
          @response = generate_rails_document_link_hover(message.value, message)
        end

        sig { params(node: SyntaxTree::ConstPathRef).void }
        def on_const_path_ref(node)
          @response = generate_rails_document_link_hover(full_constant_name(node), node)
        end

        sig { params(node: SyntaxTree::CallNode).void }
        def on_call(node)
          message = node.message
          return if message.is_a?(Symbol)

          @response = generate_rails_document_link_hover(message.value, message)
        end
      end

      private

      sig { params(name: String, node: SyntaxTree::Node).returns(T.nilable(Interface::Hover)) }
      def generate_rails_document_link_hover(name, node)
        urls = Support::RailsDocumentClient.generate_rails_document_urls(name)
        return if urls.empty?

        contents = Interface::MarkupContent.new(kind: "markdown", value: urls.join("\n\n"))
        Interface::Hover.new(range: range_from_syntax_tree_node(node), contents: contents)
      end
    end
  end
end
