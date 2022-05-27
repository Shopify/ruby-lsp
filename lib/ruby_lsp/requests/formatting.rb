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
    class Formatting
      def self.run(uri, document)
        new(uri, document).run
      end

      def initialize(uri, document)
        @uri = uri
        @document = document
        if defined?(Support::RuboCopRunner)
          @runner = Support::RuboCopRunner.new(uri, document, ["--auto-correct"])
        end
      end

      def run
        return [] if @document.syntax_errors? || !@runner

        @runner.run

        return unless formatted_text

        @document.reset(formatted_text)

        [
          LanguageServer::Protocol::Interface::TextEdit.new(
            range: LanguageServer::Protocol::Interface::Range.new(
              start: LanguageServer::Protocol::Interface::Position.new(line: 0, character: 0),
              end: LanguageServer::Protocol::Interface::Position.new(
                line: text.size,
                character: text.size
              )
            ),
            new_text: formatted_text
          ),
        ]
      end

      private

      def text
        @runner.text
      end

      def formatted_text
        @runner.formatted_text
      end
    end
  end
end
