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
          Interface::CodeLensOptions.new(resolve_provider: true)
        end
      end

      #: (GlobalState, RubyDocument | ERBDocument, Prism::Dispatcher) -> void
      def initialize(global_state, document, dispatcher)
        @response_builder = ResponseBuilders::CollectionResponseBuilder
          .new #: ResponseBuilders::CollectionResponseBuilder[Interface::CodeLens]
        super()

        @document = document
        @test_builder = ResponseBuilders::TestCollection.new #: ResponseBuilders::TestCollection
        uri = document.uri
        file_path = uri.full_path
        code_lens_config = global_state.feature_configuration(:codeLens)
        test_lenses_enabled = (!code_lens_config || code_lens_config.enabled?(:enableTestCodeLens)) &&
          file_path && File.fnmatch?(TEST_PATH_PATTERN, file_path, File::FNM_PATHNAME | File::FNM_EXTGLOB)

        if global_state.enabled_feature?(:fullTestDiscovery)
          if test_lenses_enabled
            Listeners::TestStyle.new(@test_builder, global_state, dispatcher, uri)
            Listeners::SpecStyle.new(@test_builder, global_state, dispatcher, uri)
          end
        else
          Listeners::CodeLens.new(@response_builder, global_state, uri, dispatcher)
        end

        Addon.addons.each do |addon|
          addon.create_code_lens_listener(@response_builder, uri, dispatcher)

          if global_state.enabled_feature?(:fullTestDiscovery) && test_lenses_enabled
            addon.create_discover_tests_listener(@test_builder, dispatcher, uri)
          end
        end
      end

      # @override
      #: -> Array[Interface::CodeLens]
      def perform
        @document.cache_set("rubyLsp/discoverTests", @test_builder.response)
        @response_builder.response + @test_builder.code_lens
      end
    end
  end
end
