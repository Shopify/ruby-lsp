# typed: strict
# frozen_string_literal: true

module RubyLsp
  module Requests
    class GoToDefinition < BaseRequest
      extend T::Sig

      sig { params(indexer: Indexer, uri: String, document: Document, position: Document::PositionShape).void }
      def initialize(indexer, uri, document, position)
        super(document)
        @uri = uri
        @indexer = T.let(indexer, Indexer)
        @position = T.let(document.create_scanner.find_char_position(position), Integer)
      end

      sig { override.returns(T::Array[LanguageServer::Protocol::Interface::Location]) }
      def run
        return [] unless @document.parsed?

        $stderr.puts "====== Here.... Document is parsed"

        target, _ = locate_node_and_parent(
          T.must(@document.tree), [SyntaxTree::ConstPathRef], @position
        )

        $stderr.puts "====== Here.... Target is found #{target.class}"

        locs = case target
        when SyntaxTree::Command
          message = target.message
          indexer.locs_for_symbol(message, :method)
        when SyntaxTree::CallNode
          return [] if target.message == :call

          indexer.locs_for_symbol(target.message.value, :method)
        when SyntaxTree::ConstPathRef
          constant_name = full_constant_name(target)
          $stderr.puts "====== Here.... Constant #{constant_name}"
          indexer.locs_for_symbol(constant_name, :constant)
        end

        $stderr.puts "====== Here.... Got locs #{locs}"

        return [] unless locs

        locs.map do |file, line|
          LanguageServer::Protocol::Interface::Location.new(
            uri: "file://#{file}",
            range: LanguageServer::Protocol::Interface::Range.new(
              start: LanguageServer::Protocol::Interface::Position.new(
                line: line - 1,
                character: 0,
              ),
              end: LanguageServer::Protocol::Interface::Position.new(
                line: line - 1,
                character: 0,
              ),
            ),
          )
        end
      end

      private

      sig { returns(Indexer) }
      attr_reader :indexer

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
