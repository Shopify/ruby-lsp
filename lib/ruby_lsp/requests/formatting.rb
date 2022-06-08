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
    class Formatting < BaseRequest
      extend T::Sig
      include Support::RuboCopRunner::CallbackHandler

      sig { params(uri: String, document: Document).void }
      def initialize(uri, document)
        super(document)

        @uri = uri
        @runner = T.let(Support::RuboCopRunner.formatting_instance, Support::RuboCopRunner)
      end

      sig { override.returns(T.nilable(T.all(T::Array[LanguageServer::Protocol::Interface::TextEdit], Object))) }
      def run
        @runner.run(@uri, @document, self)

        formatted_text = @runner.stdin
        return unless formatted_text

        size = T.must(@runner.text).size

        [
          LanguageServer::Protocol::Interface::TextEdit.new(
            range: LanguageServer::Protocol::Interface::Range.new(
              start: LanguageServer::Protocol::Interface::Position.new(line: 0, character: 0),
              end: LanguageServer::Protocol::Interface::Position.new(
                line: size,
                character: size
              )
            ),
            new_text: formatted_text
          ),
        ]
      end

      sig { override.params(offenses: T::Array[RuboCop::Cop::Offense]).void }
      def callback(offenses); end
    end
  end
end
