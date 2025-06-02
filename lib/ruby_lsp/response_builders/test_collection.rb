# typed: strict
# frozen_string_literal: true

module RubyLsp
  module ResponseBuilders
    #: [ResponseType = Requests::Support::TestItem]
    class TestCollection < ResponseBuilder
      #: Array[Interface::CodeLens]
      attr_reader :code_lens

      #: -> void
      def initialize
        super
        @items = {} #: Hash[String, ResponseType]
        @code_lens = [] #: Array[Interface::CodeLens]
      end

      #: (ResponseType item) -> void
      def add(item)
        @items[item.id] = item
      end

      #: (ResponseType item) -> void
      def add_code_lens(item)
        arguments = [item.uri.to_standardized_path, item.id]
        start = item.range.start
        range = Interface::Range.new(
          start: start,
          end: Interface::Position.new(line: start.line, character: start.character + 1),
        )

        @code_lens << Interface::CodeLens.new(
          range: range,
          data: { arguments: arguments, kind: "run_test" },
        )

        @code_lens << Interface::CodeLens.new(
          range: range,
          data: { arguments: arguments, kind: "run_test_in_terminal" },
        )

        @code_lens << Interface::CodeLens.new(
          range: range,
          data: { arguments: arguments, kind: "debug_test" },
        )
      end

      #: (String id) -> ResponseType?
      def [](id)
        @items[id]
      end

      # @override
      #: -> Array[ResponseType]
      def response
        @items.values
      end
    end
  end
end
