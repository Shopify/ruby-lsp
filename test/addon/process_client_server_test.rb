# typed: true
# frozen_string_literal: true

require "test_helper"
require "ruby_lsp/addon/process_client"

module RubyLsp
  class Addon
    class ProcessClientServerTest < Minitest::Test
      class FakeClient < ProcessClient
        def initialize(addon)
          server_path = File.expand_path("../fake_process_server.rb", __FILE__)
          super(addon, "bundle exec ruby #{server_path}")
        end

        def echo(message)
          make_request("echo", { message: message })
        end

        def send_unknown_request
          send_message("unknown_request")
        end

        def log_output(message)
          # No-op for testing to reduce noise
        end

        private

        def handle_initialize_response(response)
          raise InitializationError, "Server not initialized" unless response[:initialized]
        end

        def register_exit_handler
          # No-op for testing
        end
      end

      def setup
        @addon = create_fake_addon
        @client = FakeClient.new(@addon)
      end

      def teardown
        @client.shutdown
        assert_predicate(@client, :stopped?, "Client should be stopped after shutdown")
        RubyLsp::Addon.addons.clear
        RubyLsp::Addon.addon_classes.clear
      end

      def test_client_server_communication
        response = @client.echo("Hello, World!")
        assert_equal({ echo_result: "Hello, World!" }, response)
      end

      def test_server_initialization
        # The server is already initialized in setup, so we just need to verify it didn't raise an error
        assert_instance_of(FakeClient, @client)
      end

      def test_server_ignores_unknown_request
        @client.send_unknown_request
        response = @client.echo("Hey!")
        assert_equal({ echo_result: "Hey!" }, response)
      end

      private

      def create_fake_addon
        Class.new(Addon) do
          def name
            "FakeAddon"
          end

          def activate(global_state, outgoing_queue)
            # No-op for testing
          end

          def deactivate
            # No-op for testing
          end
        end.new
      end
    end
  end
end
