# typed: strict
# frozen_string_literal: true

module RubyLsp
  module Requests
    # ![Formatting symbol demo](../../formatting.gif)
    #
    # The [formatting](https://microsoft.github.io/language-server-protocol/specification#textDocument_formatting)
    # request uses RuboCop to fix auto-correctable offenses in the document. This requires enabling format on save and
    # registering the ruby-lsp as the Ruby formatter.
    #
    # The `rubyLsp.formatter` setting specifies which formatter to use.
    # If set to `auto` then it behaves as follows:
    # * It will use RuboCop if it is part of the bundle.
    # * If RuboCop is not available, and `syntax_tree` is a direct dependency, it will use that.
    # * Otherwise, no formatting will be applied.
    #
    # # Example
    #
    # ```ruby
    # def say_hello
    # puts "Hello" # --> formatting: fixes the indentation on save
    # end
    # ```
    class Formatting < Request
      extend T::Sig

      class Error < StandardError; end

      sig { params(global_state: GlobalState, document: Document).void }
      def initialize(global_state, document)
        super()
        @document = document
        @active_formatter = T.let(global_state.active_formatter, T.nilable(Support::Formatter))
        @uri = T.let(document.uri, URI::Generic)
      end

      sig { override.returns(T.nilable(T.all(T::Array[Interface::TextEdit], Object))) }
      def perform
        return unless @active_formatter
        return if @document.syntax_error?

        formatted_text = @active_formatter.run_formatting(@uri, @document)
        return unless formatted_text

        size = @document.source.size
        return if formatted_text.size == size && formatted_text == @document.source

        [
          Interface::TextEdit.new(
            range: Interface::Range.new(
              start: Interface::Position.new(line: 0, character: 0),
              end: Interface::Position.new(line: size, character: size),
            ),
            new_text: formatted_text,
          ),
        ]
      end
    end
  end
end
