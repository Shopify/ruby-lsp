# typed: strict
# frozen_string_literal: true

module RubyLsp
  module Requests
    # The [range formatting](https://microsoft.github.io/language-server-protocol/specification#textDocument_rangeFormatting)
    # is used to format a selection or to format on paste.
    class RangeFormatting < Request
      #: (GlobalState global_state, RubyDocument document, Hash[Symbol, untyped] params) -> void
      def initialize(global_state, document, params)
        super()
        @document = document
        @uri = document.uri #: URI::Generic
        @params = params
        @active_formatter = global_state.active_formatter #: Support::Formatter?
      end

      # @override
      #: -> Array[Interface::TextEdit]?
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

        code_units_cache = @document.code_units_cache

        [
          Interface::TextEdit.new(
            range: Interface::Range.new(
              start: Interface::Position.new(
                line: location.start_line - 1,
                character: location.cached_start_code_units_column(code_units_cache),
              ),
              end: Interface::Position.new(
                line: location.end_line - 1,
                character: location.cached_end_code_units_column(code_units_cache),
              ),
            ),
            new_text: formatted_text.strip,
          ),
        ]
      end
    end
  end
end
