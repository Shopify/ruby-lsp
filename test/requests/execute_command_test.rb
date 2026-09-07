# typed: true
# frozen_string_literal: true

require "test_helper"

module RubyLsp
  class ExecuteCommandTest < Minitest::Test
    def setup
      @addon_class = Class.new(Addon) do
        def activate(global_state, outgoing_queue); end
        def deactivate; end

        def name
          "Command Add-on"
        end

        def version
          "0.1.0"
        end

        def commands
          ["commandAddon.echo"]
        end

        def execute_command(command, arguments)
          { command: command, arguments: arguments }
        end
      end

      Addon.addon_classes.delete(@addon_class)
    end

    def teardown
      Addon.addons.select { |addon| addon.is_a?(@addon_class) }.each(&:deactivate)
      Addon.addons.delete_if { |addon| addon.is_a?(@addon_class) }
    end

    def test_executes_an_addon_command
      Addon.addons << @addon_class.new

      with_server(load_addons: false) do |server, _uri|
        server.process_message(
          id: 1,
          method: "workspace/executeCommand",
          params: {
            command: "commandAddon.echo",
            arguments: ["hello"],
          },
        )

        result = server.pop_response
        assert_instance_of(Result, result)
        assert_equal(
          { command: "commandAddon.echo", arguments: ["hello"] },
          result.response,
        )
      end
    end

    def test_returns_an_error_for_an_unknown_command
      Addon.addons << @addon_class.new

      with_server(load_addons: false) do |server, _uri|
        server.process_message(
          id: 1,
          method: "workspace/executeCommand",
          params: {
            command: "commandAddon.missing",
            arguments: [],
          },
        )

        error = server.pop_response
        assert_instance_of(Error, error)
        assert_equal(Constant::ErrorCodes::INVALID_PARAMS, error.code)
        assert_equal("Unknown command: commandAddon.missing", error.message)
      end
    end

    def test_registers_addon_commands_after_initialization
      Addon.addons << @addon_class.new

      server = Server.new(test_mode: true)
      server.global_state.apply_options({
        capabilities: {
          workspace: {
            executeCommand: {
              dynamicRegistration: true,
            },
          },
        },
      })
      server.stubs(:load_addons)
      server.stubs(:perform_initial_indexing)
      server.process_message(method: "initialized")

      registration = server.pop_response
      assert_instance_of(Request, registration)
      assert_equal("client/registerCapability", registration.method)

      registered_capability = registration.params.registrations.first
      assert_equal("addon-commands", registered_capability.id)
      assert_equal("workspace/executeCommand", registered_capability.method)
      assert_equal(["commandAddon.echo"], registered_capability.register_options.commands)
    ensure
      server&.run_shutdown
    end
  end
end
