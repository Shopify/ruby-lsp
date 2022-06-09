# typed: strict
# frozen_string_literal: true

module RubyLsp
  module Requests
    module Support
      class SelectionRange < LanguageServer::Protocol::Interface::SelectionRange
        extend T::Sig

        sig { params(position: Document::PositionShape).returns(T::Boolean) }
        def cover?(position)
          line_range = (range.start.line..range.end.line)
          character_range = (range.start.character..range.end.character)

          line_range.cover?(position[:line]) && character_range.cover?(position[:character])
        end
      end
    end
  end
end
