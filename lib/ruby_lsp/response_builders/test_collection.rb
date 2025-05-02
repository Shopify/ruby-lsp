# typed: strict
# frozen_string_literal: true

module RubyLsp
  module ResponseBuilders
    class TestCollection < ResponseBuilder
      extend T::Generic

      ResponseType = type_member { { fixed: Requests::Support::TestItem } }

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
        range = item.range
        arguments = [item.uri.to_standardized_path, item.id]

        @code_lens << Interface::CodeLens.new(
          range: range,
          command: Interface::Command.new(
            title: "▶ Run",
            command: "rubyLsp.runTest",
            arguments: arguments,
          ),
        )

        @code_lens << Interface::CodeLens.new(
          range: range,
          command: Interface::Command.new(
            title: "▶ Run In Terminal",
            command: "rubyLsp.runTestInTerminal",
            arguments: arguments,
          ),
        )

        @code_lens << Interface::CodeLens.new(
          range: range,
          command: Interface::Command.new(
            title: "⚙ Debug",
            command: "rubyLsp.debugTest",
            arguments: arguments,
          ),
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
