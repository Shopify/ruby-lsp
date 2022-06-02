# typed: true
# frozen_string_literal: true

module RubyLsp
  module Requests
    module Support
      class SelectionRange < LanguageServer::Protocol::Interface::SelectionRange
        def cover?(position)
          line_range = (range.start.line..range.end.line)
          character_range = (range.start.character..range.end.character)

          line_range.cover?(position[:line]) && character_range.cover?(position[:character])
        end
      end
    end
  end
end
