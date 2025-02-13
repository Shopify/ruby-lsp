# typed: strict
# frozen_string_literal: true

require "ruby_lsp/listeners/test_style"

module RubyLsp
  module Requests
    # This is a custom request to ask the server to parse a test file and discover all available examples in it. Add-ons
    # can augment the behavior through listeners, allowing them to handle discovery for different frameworks
    class DiscoverTests < Request
      extend T::Sig
      include Support::Common

      sig { params(global_state: GlobalState, document: RubyDocument, dispatcher: Prism::Dispatcher).void }
      def initialize(global_state, document, dispatcher)
        super()
        @global_state = global_state
        @document = document
        @dispatcher = dispatcher
        @response_builder = T.let(ResponseBuilders::TestCollection.new, ResponseBuilders::TestCollection)
        @index = T.let(global_state.index, RubyIndexer::Index)
      end

      sig { override.returns(T::Array[Support::TestItem]) }
      def perform
        uri = @document.uri

        # We normally only index test files once they are opened in the editor to save memory and avoid doing
        # unnecessary work. If the file is already opened and we already indexed it, then we can just discover the tests
        # straight away.
        #
        # However, if the user navigates to a specific test file from the explorer with nothing opened in the UI, then
        # we will not have indexed the test file yet and trying to linearize the ancestor of the class will fail. In
        # this case, we have to instantiate the indexer listener first, so that we insert classes, modules and methods
        # in the index first and then discover the tests, all in the same traversal.
        if @index.entries_for(uri.to_s)
          Listeners::TestStyle.new(@response_builder, @global_state, @dispatcher, @document.uri)
          @dispatcher.visit(@document.parse_result.value)
        else
          @global_state.synchronize do
            RubyIndexer::DeclarationListener.new(
              @index,
              @dispatcher,
              @document.parse_result,
              uri,
              collect_comments: true,
            )

            Listeners::TestStyle.new(@response_builder, @global_state, @dispatcher, @document.uri)

            # Dispatch the events both for indexing the test file and discovering the tests. The order here is
            # important because we need the index to be aware of the existing classes/modules/methods before the test
            # listeners can do their work
            @dispatcher.visit(@document.parse_result.value)
          end
        end

        @response_builder.response
      end
    end
  end
end
