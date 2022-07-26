# typed: strict
# frozen_string_literal: true

module RubyLsp
  module Requests
    # ![Document link demo](../../misc/document_link.gif)
    #
    # The [document link](https://microsoft.github.io/language-server-protocol/specification#textDocument_documentLink)
    # makes `# source://PATH_TO_FILE:line` comments in a Ruby/RBI file clickable if the file exists.
    # When the user clicks the link, it'll take the user to that location.
    #
    # # Example
    #
    # ```ruby
    # # source://syntax_tree-3.2.1/lib/syntax_tree.rb:51 <- it will be clickable and will take the user to that location
    # def format(source, maxwidth = T.unsafe(nil))
    # end
    # ```
    class DocumentLink < BaseRequest
      extend T::Sig

      RUBY_ROOT = "RUBY_ROOT"

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

        file_path = if match[:path].start_with?(RUBY_ROOT)
          match[:path].sub(RUBY_ROOT, RbConfig::CONFIG["rubylibdir"])
        else
          File.join(Bundler.bundle_path, "gems", match[:path])
        end
        return unless File.exist?(file_path)

        target = "file://#{file_path}##{match[:line]}"

        @links << LanguageServer::Protocol::Interface::DocumentLink.new(
          range: range_from_syntax_tree_node(node),
          target: target,
          tooltip: "Jump to #{target.delete_prefix("file://")}"
        )
      end
    end
  end
end
