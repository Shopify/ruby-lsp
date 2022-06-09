# typed: strict
# frozen_string_literal: true

module RubyLsp
  module Requests
    # The [code actions](https://microsoft.github.io/language-server-protocol/specification#textDocument_codeAction)
    # request informs the editor of RuboCop quick fixes that can be applied. These are accesible by hovering over a
    # specific diagnostic.
    #
    # # Example
    #
    # ```ruby
    # def say_hello
    # puts "Hello" # --> code action: quick fix indentation
    # end
    # ```
    class CodeActions
      extend T::Sig

      sig do
        params(
          uri: String,
          document: Document,
          range: T::Range[Integer]
        ).returns(T::Array[LanguageServer::Protocol::Interface::CodeAction])
      end
      def self.run(uri, document, range)
        new(uri, document, range).run
      end

      sig do
        params(
          uri: String,
          document: Document,
          range: T::Range[Integer]
        ).void
      end
      def initialize(uri, document, range)
        @document = document
        @uri = uri
        @range = range
      end

      sig { returns(T::Array[LanguageServer::Protocol::Interface::CodeAction]) }
      def run
        diagnostics = Diagnostics.run(@uri, @document)
        corrections = diagnostics.select { |diagnostic| diagnostic.correctable? && diagnostic.in_range?(@range) }
        return [] if corrections.empty?

        corrections.map!(&:to_lsp_code_action)
      end
    end
  end
end
