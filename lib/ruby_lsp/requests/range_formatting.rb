# typed: strict
# frozen_string_literal: true

module RubyLsp
  module Requests
    # The [range formatting](https://microsoft.github.io/language-server-protocol/specification#textDocument_rangeFormatting)
    # is used to format a selection or to format on paste.
    class RangeFormatting < Request
      extend T::Sig

      sig { params(global_state: GlobalState, document: RubyDocument, params: T::Hash[Symbol, T.untyped]).void }
      def initialize(global_state, document, params)
        super()
        @document = document
        @uri = T.let(document.uri, URI::Generic)
        @params = params
        @active_formatter = T.let(global_state.active_formatter, T.nilable(Support::Formatter))
      end

      sig { override.returns(T.nilable(T::Array[Interface::TextEdit])) }
      def perform
        return unless @active_formatter
        return if @document.syntax_error?

        target = @document.locate_first_within_range(@params[:range])
        return unless target

        location = target.location

        formatted_text = @active_formatter.run_range_formatting(
          @uri,
          target.slice,
          location.start_column / 2,
        )
        return unless formatted_text

        [
          Interface::TextEdit.new(
            range: Interface::Range.new(
              start: Interface::Position.new(
                line: location.start_line - 1,
                character: location.start_code_units_column(@document.encoding),
              ),
              end: Interface::Position.new(
                line: location.end_line - 1,
                character: location.end_code_units_column(@document.encoding),
              ),
            ),
            new_text: formatted_text.strip,
          ),
        ]
      end
    end
  end
end
