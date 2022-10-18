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
    class Hover < BaseRequest
      extend T::Sig

      sig { params(document: Document, position: Document::PositionShape).void }
      def initialize(document, position)
        super(document)

        @position = T.let(Document::Scanner.new(document.source).find_position(position), Integer)
      end

      sig { override.returns(T.nilable(LanguageServer::Protocol::Interface::Hover)) }
      def run
        return unless @document.parsed?

        target, _ = locate_node_and_parent(
          T.must(@document.tree), [SyntaxTree::Command, SyntaxTree::FCall, SyntaxTree::ConstPathRef], @position
        )

        case target
        when SyntaxTree::Command
          message = target.message
          generate_rails_document_link_hover(message.value, message)
        when SyntaxTree::FCall
          message = target.value
          generate_rails_document_link_hover(message.value, message)
        when SyntaxTree::ConstPathRef
          constant_name = full_constant_name(target)
          generate_rails_document_link_hover(constant_name, target)
        end
      end

      private

      sig do
        params(name: String, node: SyntaxTree::Node).returns(T.nilable(LanguageServer::Protocol::Interface::Hover))
      end
      def generate_rails_document_link_hover(name, node)
        urls = Support::RailsDocumentClient.generate_rails_document_urls(name)

        return if urls.empty?

        contents = LanguageServer::Protocol::Interface::MarkupContent.new(
          kind: "markdown",
          value: urls.join("\n\n"),
        )
        LanguageServer::Protocol::Interface::Hover.new(
          range: range_from_syntax_tree_node(node),
          contents: contents,
        )
      end
    end
  end
end
