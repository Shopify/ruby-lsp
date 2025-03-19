# typed: strict
# frozen_string_literal: true

require "shellwords"

require "ruby_lsp/listeners/code_lens"

module RubyLsp
  module Requests
    # The
    # [code lens](https://microsoft.github.io/language-server-protocol/specification#textDocument_codeLens)
    # request informs the editor of runnable commands such as testing and debugging.
    class CodeLens < Request
      class << self
        #: -> Interface::CodeLensOptions
        def provider
          Interface::CodeLensOptions.new(resolve_provider: false)
        end
      end

      #: (GlobalState global_state, URI::Generic uri, Prism::Dispatcher dispatcher) -> void
      def initialize(global_state, uri, dispatcher)
        @response_builder = ResponseBuilders::CollectionResponseBuilder[Interface::CodeLens]
          .new #: ResponseBuilders::CollectionResponseBuilder[Interface::CodeLens]
        super()
        Listeners::CodeLens.new(@response_builder, global_state, uri, dispatcher)

        Addon.addons.each do |addon|
          addon.create_code_lens_listener(@response_builder, uri, dispatcher)
        end
      end

      # @override
      #: -> Array[Interface::CodeLens]
      def perform
        @response_builder.response
      end
    end
  end
end
