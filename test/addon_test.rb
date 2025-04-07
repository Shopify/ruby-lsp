# typed: true
# frozen_string_literal: true

require "test_helper"

module RubyLsp
  class AddonTest < Minitest::Test
    def setup
      @addon = Class.new(Addon) do
        attr_reader :activated, :field, :settings

        def initialize
          @field = 123
          super
        end

        def activate(global_state, outgoing_queue)
          @activated = true
          @settings = global_state.settings_for_addon(name)
        end

        def name
          "My Add-on"
        end

        def version
          "0.1.0"
        end
      end
      @global_state = GlobalState.new
      @outgoing_queue = Thread::Queue.new
    end

    def teardown
      RubyLsp::Addon.file_watcher_addons.clear
      RubyLsp::Addon.addon_classes.clear
      RubyLsp::Addon.addons.clear
      @outgoing_queue.close
    end

    def test_registering_an_addon_invokes_activate_on_initialized
      Addon.load_addons(@global_state, @outgoing_queue)
      server = RubyLsp::Server.new

      capture_subprocess_io do
        server.process_message({ method: "initialized" })
      end

      addon_instance = T.must(Addon.addons.find { |addon| addon.is_a?(@addon) })
      assert_predicate(addon_instance, :activated)
    ensure
      T.must(server).run_shutdown
    end

    def test_addons_are_automatically_tracked
      Addon.load_addons(@global_state, @outgoing_queue)

      addon = Addon.addons.find { |addon| addon.is_a?(@addon) }
      assert_equal(123, T.unsafe(addon).field)
    end

    def test_loading_addons_initializes_them
      Addon.load_addons(@global_state, @outgoing_queue)
      assert(
        Addon.addons.any? { |addon| addon.is_a?(@addon) },
        "Expected add-on to be automatically tracked",
      )
    end

    def test_load_addons_returns_errors
      Class.new(Addon) do
        def activate(global_state, outgoing_queue)
          raise StandardError, "Failed to activate"
        end

        def name
          "My Add-on"
        end

        def version
          "0.1.0"
        end
      end

      Addon.load_addons(@global_state, @outgoing_queue)
      error_addon = T.must(Addon.addons.find(&:error?))

      assert_predicate(error_addon, :error?)
      assert_equal(<<~MESSAGE, error_addon.formatted_errors)
        My Add-on:
          Failed to activate
      MESSAGE
    end

    def test_automatically_identifies_file_watcher_addons
      klass = Class.new(::RubyLsp::Addon) do
        def activate(global_state, outgoing_queue); end
        def deactivate; end

        def workspace_did_change_watched_files(changes); end
      end

      Addon.load_addons(@global_state, @outgoing_queue)
      addon = Addon.file_watcher_addons.find { |a| a.is_a?(klass) }
      refute_nil(addon)
    end

    def test_get_an_addon_by_name
      Addon.load_addons(@global_state, @outgoing_queue)
      addon = Addon.get("My Add-on", "0.1.0")
      assert_equal("My Add-on", addon.name)
    end

    def test_raises_if_an_addon_cannot_be_found
      Addon.load_addons(@global_state, @outgoing_queue)
      assert_raises(Addon::AddonNotFoundError) do
        Addon.get("Invalid Addon", "0.1.0")
      end
    end

    def test_raises_if_an_addon_version_does_not_match
      Addon.load_addons(@global_state, @outgoing_queue)
      assert_raises(Addon::IncompatibleApiError) do
        Addon.get("My Add-on", "> 15.0.0")
      end
    end

    def test_raises_if_no_version_constraints_are_passed
      Addon.load_addons(@global_state, @outgoing_queue)
      assert_raises(Addon::IncompatibleApiError) do
        Addon.get("My Add-on")
      end
    end

    def test_addons_receive_settings
      @global_state.apply_options({
        initializationOptions: {
          addonSettings: {
            "My Add-on" => { something: false },
          },
        },
      })

      Addon.load_addons(@global_state, @outgoing_queue)

      addon = Addon.get("My Add-on", "0.1.0")
      assert_equal({ something: false }, T.unsafe(addon).settings)
    end

    def test_depend_on_constraints
      Addon.load_addons(@global_state, @outgoing_queue)
      assert_raises(Addon::IncompatibleApiError) do
        Addon.depend_on_ruby_lsp!(">= 10.0.0")
      end

      Addon.depend_on_ruby_lsp!(">= 0.18.0", "< 0.30.0")
    end

    def test_project_specific_addons
      Dir.mktmpdir do |dir|
        addon_dir = File.join(dir, "lib", "ruby_lsp", "test_addon")
        FileUtils.mkdir_p(addon_dir)
        File.write(File.join(addon_dir, "addon.rb"), <<~RUBY)
          class ProjectAddon < RubyLsp::Addon
            attr_reader :hello

            def activate(global_state, outgoing_queue)
              @hello = true
            end

            def name
              "Project Addon"
            end

            def version
              "0.1.0"
            end
          end
        RUBY

        @global_state.apply_options({
          workspaceFolders: [{ uri: URI::Generic.from_path(path: dir).to_s }],
        })
        Addon.load_addons(@global_state, @outgoing_queue)

        addon = Addon.get("Project Addon", "0.1.0")
        assert_equal("Project Addon", addon.name)
        assert_predicate(T.unsafe(addon), :hello)
      end
    end

    def test_an_addon_calling_exit_or_raising_does_not_quit_lsp
      Addon.load_addons(@global_state, @outgoing_queue)

      addon = Addon.get("My Add-on", "0.1.0")

      listeners = addon.public_methods.grep(/_listener$/)
      other_commands = [
        :handle_window_show_message_response,
        :resolve_test_commands,
        :workspace_did_change_watched_files,
      ]

      commands_that_should_not_quit_lsp = [*listeners, *other_commands]

      failures = []

      commands_that_should_not_quit_lsp.each do |command|
        # Check how `exit` is handled
        addon.define_singleton_method(command) { Kernel.exit }

        begin
          capture_io { Addon.notify(addon, command, nil) }
        rescue SystemExit
          failures << "Addon.notify(addon, #{command.inspect}, args) should not be able to exit the LSP process"
        end

        # Check how `abort` is handled
        addon.define_singleton_method(command) { Kernel.abort }

        begin
          capture_io { Addon.notify(addon, command, nil) }
        rescue SystemExit
          failures << "Addon.notify(addon, #{command.inspect}, args) should not be able to abort the LSP process"
        end

        # Check how `raise` is handled
        addon.define_singleton_method(command) { raise StandardError }

        begin
          capture_io { Addon.notify(addon, command, nil) }
        rescue StandardError
          failures << "Addon.notify(addon, #{command.inspect}, args) should not raise an error"
        end
      end

      assert_empty(failures, failures.join("\n"))
    end
  end
end
