# typed: strict
# frozen_string_literal: true

module RubyLsp
  module Requests
    # The [formatting](https://microsoft.github.io/language-server-protocol/specification#textDocument_formatting)
    # request uses RuboCop to fix auto-correctable offenses in the document. This requires enabling format on save and
    # registering the ruby-lsp as the Ruby formatter.
    class Formatting < Request
      class Error < StandardError; end

      class << self
        #: -> TrueClass
        def provider
          true
        end
      end

      #: (GlobalState global_state, RubyDocument document) -> void
      def initialize(global_state, document)
        super()
        @document = document
        @active_formatter = global_state.active_formatter #: Support::Formatter?
        @uri = document.uri #: URI::Generic
      end

      # @override
      #: -> (Array[Interface::TextEdit] & Object)?
      def perform
        return unless @active_formatter
        return if @document.syntax_error?

        # We don't format erb documents yet

        formatted_text = @active_formatter.run_formatting(@uri, @document)
        return unless formatted_text

        lines = @document.source.lines
        size = @document.source.size

        return if formatted_text.size == size && formatted_text == @document.source

        [
          Interface::TextEdit.new(
            range: Interface::Range.new(
              start: Interface::Position.new(line: 0, character: 0),
              end: Interface::Position.new(line: lines.size, character: 0),
            ),
            new_text: formatted_text,
          ),
        ]
      end
    end
  end
end
