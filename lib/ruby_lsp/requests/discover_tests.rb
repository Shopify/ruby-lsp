# typed: strict
# frozen_string_literal: true

require "ruby_lsp/listeners/test_discovery"
require "ruby_lsp/listeners/test_style"
require "ruby_lsp/listeners/spec_style"

module RubyLsp
  module Requests
    # This is a custom request to ask the server to parse a test file and discover all available examples in it. Add-ons
    # can augment the behavior through listeners, allowing them to handle discovery for different frameworks
    class DiscoverTests < Request
      include Support::Common

      #: (GlobalState global_state, RubyDocument document, Prism::Dispatcher dispatcher) -> void
      def initialize(global_state, document, dispatcher)
        super()
        @global_state = global_state
        @document = document
        @dispatcher = dispatcher
        @response_builder = ResponseBuilders::TestCollection.new(document.encoding, document.parse_result) #: ResponseBuilders::TestCollection
      end

      # @override
      #: -> Array[Support::TestItem]
      def perform
        Listeners::TestStyle.new(@response_builder, @global_state, @dispatcher, @document.uri)
        Listeners::SpecStyle.new(@response_builder, @global_state, @dispatcher, @document.uri)

        Addon.addons.each do |addon|
          addon.create_discover_tests_listener(@response_builder, @dispatcher, @document.uri)
        end

        @dispatcher.visit(@document.ast)
        @response_builder.response
      end
    end
  end
end
