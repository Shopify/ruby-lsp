# typed: strict
# frozen_string_literal: true

module RubyLsp
  module Requests
    class DocumentLink < BaseRequest
      extend T::Sig

      sig { params(document: Document).void }
      def initialize(document)
        super

        @links = T.let([], T::Array[LanguageServer::Protocol::Interface::DocumentLink])
      end

      sig { override.returns(T.all(T::Array[LanguageServer::Protocol::Interface::DocumentLink], Object)) }
      def run
        visit(@document.tree)
        @links
      end

      sig { params(node: SyntaxTree::Comment).void }
      def visit_comment(node)
        match = node.value.match(%r{source://(?<path>.*):(?<line>\d+)$})
        return unless match

        file_path = File.join(Bundler.bundle_path, "gems", match[:path])
        return unless File.exist?(file_path)

        target = "file://#{file_path}##{match[:line]}"

        @links << LanguageServer::Protocol::Interface::DocumentLink.new(
          range: range_from_syntax_tree_node(node),
          target: target,
          tooltip: "Jump to the source"
        )
      end
    end
  end
end
