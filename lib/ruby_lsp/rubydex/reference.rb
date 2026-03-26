# typed: strict
# frozen_string_literal: true

module Rubydex
  class ConstantReference
    #: () -> RubyLsp::Interface::Range
    def to_lsp_range
      loc = location

      RubyLsp::Interface::Range.new(
        start: RubyLsp::Interface::Position.new(line: loc.start_line, character: loc.start_column),
        end: RubyLsp::Interface::Position.new(line: loc.end_line, character: loc.end_column),
      )
    end
  end
end
