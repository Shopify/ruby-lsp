# typed: strict
# frozen_string_literal: true

module RubyLsp
  module Requests
    # ![Code actions demo](../../misc/code_actions.gif)
    #
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
    class CodeActions < BaseRequest
      extend T::Sig

      sig do
        params(
          uri: String,
          document: Document,
          range: T::Range[Integer],
        ).void
      end
      def initialize(uri, document, range)
        super(document)

        @uri = uri
        @range = range
      end

      sig { override.returns(T.all(T::Array[LanguageServer::Protocol::Interface::CodeAction], Object)) }
      def run
        diagnostics = Diagnostics.new(@uri, @document).run
        corrections = diagnostics.select do |diagnostic|
          diagnostic.correctable? && T.cast(diagnostic, Support::RuboCopDiagnostic).in_range?(@range)
        end
        return [] if corrections.empty?

        T.cast(corrections, T::Array[Support::RuboCopDiagnostic]).map!(&:to_lsp_code_action)
      end
    end
  end
end
