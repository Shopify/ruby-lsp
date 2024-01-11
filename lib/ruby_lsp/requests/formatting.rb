# typed: strict
# frozen_string_literal: true

require "ruby_lsp/requests/support/rubocop_formatting_runner"
require "ruby_lsp/requests/support/syntax_tree_formatting_runner"

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
      class Error < StandardError; end
      class InvalidFormatter < StandardError; end

      @formatters = T.let({}, T::Hash[String, Support::FormatterRunner])

      class << self
        extend T::Sig

        sig { returns(T::Hash[String, Support::FormatterRunner]) }
        attr_reader :formatters

        sig { params(identifier: String, instance: Support::FormatterRunner).void }
        def register_formatter(identifier, instance)
          @formatters[identifier] = instance
        end
      end

      if defined?(Support::RuboCopFormattingRunner)
        register_formatter("rubocop", Support::RuboCopFormattingRunner.instance)
      end

      if defined?(Support::SyntaxTreeFormattingRunner)
        register_formatter("syntax_tree", Support::SyntaxTreeFormattingRunner.instance)
      end

      extend T::Sig

      sig { params(document: Document, formatter: String).void }
      def initialize(document, formatter: "auto")
        super()
        @document = document
        @uri = T.let(document.uri, URI::Generic)
        @formatter = formatter
      end

      sig { override.returns(T.nilable(T.all(T::Array[Interface::TextEdit], Object))) }
      def perform
        return if @formatter == "none"
        return if @document.syntax_error?

        formatted_text = formatted_file
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

      private

      sig { returns(T.nilable(String)) }
      def formatted_file
        formatter_runner = Formatting.formatters[@formatter]
        raise InvalidFormatter, "Formatter is not available: #{@formatter}" unless formatter_runner

        formatter_runner.run(@uri, @document)
      end
    end
  end
end
