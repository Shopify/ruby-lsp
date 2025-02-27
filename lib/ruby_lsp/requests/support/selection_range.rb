# typed: strict
# frozen_string_literal: true

module RubyLsp
  module Requests
    module Support
      class SelectionRange < Interface::SelectionRange
        #: (Hash[Symbol, untyped] position) -> bool
        def cover?(position)
          start_covered = range.start.line < position[:line] ||
            (range.start.line == position[:line] && range.start.character <= position[:character])
          end_covered = range.end.line > position[:line] ||
            (range.end.line == position[:line] && range.end.character >= position[:character])
          start_covered && end_covered
        end
      end
    end
  end
end
