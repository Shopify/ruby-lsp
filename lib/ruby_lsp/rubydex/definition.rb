# typed: strict
# frozen_string_literal: true

module Rubydex
  class Definition
    #: () -> RubyLsp::Interface::Range
    def to_lsp_selection_range
      loc = location

      RubyLsp::Interface::Range.new(
        start: RubyLsp::Interface::Position.new(line: loc.start_line, character: loc.start_column),
        end: RubyLsp::Interface::Position.new(line: loc.end_line, character: loc.end_column),
      )
    end

    #: () -> RubyLsp::Interface::Location
    def to_lsp_selection_location
      location = self.location

      RubyLsp::Interface::Location.new(
        uri: location.uri,
        range: RubyLsp::Interface::Range.new(
          start: RubyLsp::Interface::Position.new(line: location.start_line, character: location.start_column),
          end: RubyLsp::Interface::Position.new(line: location.end_line, character: location.end_column),
        ),
      )
    end

    #: () -> RubyLsp::Interface::Range?
    def to_lsp_name_range
      loc = name_location
      return unless loc

      RubyLsp::Interface::Range.new(
        start: RubyLsp::Interface::Position.new(line: loc.start_line, character: loc.start_column),
        end: RubyLsp::Interface::Position.new(line: loc.end_line, character: loc.end_column),
      )
    end

    #: () -> RubyLsp::Interface::Location?
    def to_lsp_name_location
      location = name_location
      return unless location

      RubyLsp::Interface::Location.new(
        uri: location.uri,
        range: RubyLsp::Interface::Range.new(
          start: RubyLsp::Interface::Position.new(line: location.start_line, character: location.start_column),
          end: RubyLsp::Interface::Position.new(line: location.end_line, character: location.end_column),
        ),
      )
    end
  end
end
