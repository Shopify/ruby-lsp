# typed: strict
# frozen_string_literal: true

module RubyLsp
  module Requests
    # The [formatting](https://microsoft.github.io/language-server-protocol/specification#textDocument_formatting)
    # request uses RuboCop to fix auto-correctable offenses in the document. This requires enabling format on save and
    # registering the ruby-lsp as the Ruby formatter.
    #
    # # Example
    #
    # ```ruby
    # def say_hello
    # puts "Hello" # --> formatting: fixes the indentation on save
    # end
    # ```
    class Formatting < RuboCopRequest
      extend T::Sig
      RUBOCOP_FLAGS = T.let((COMMON_RUBOCOP_FLAGS + ["--autocorrect"]).freeze, T::Array[String])

      sig { params(uri: String, document: Document).void }
      def initialize(uri, document)
        super
        @formatted_text = T.let(nil, T.nilable(String))
      end

      sig { override.returns(T.nilable(T::Array[LanguageServer::Protocol::Interface::TextEdit])) }
      def run
        super

        @formatted_text = @options[:stdin] # Rubocop applies the corrections on stdin
        return unless @formatted_text

        [
          LanguageServer::Protocol::Interface::TextEdit.new(
            range: LanguageServer::Protocol::Interface::Range.new(
              start: LanguageServer::Protocol::Interface::Position.new(line: 0, character: 0),
              end: LanguageServer::Protocol::Interface::Position.new(
                line: text.size,
                character: text.size
              )
            ),
            new_text: @formatted_text
          ),
        ]
      end

      private

      sig { returns(T::Array[String]) }
      def rubocop_flags
        RUBOCOP_FLAGS
      end
    end
  end
end
