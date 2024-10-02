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
      Addon.load_addons(@global_state, @outgoing_queue)
    end

    def teardown
      RubyLsp::Addon.addon_classes.clear
      RubyLsp::Addon.addons.clear
      @outgoing_queue.close
    end

    def test_registering_an_addon_invokes_activate_on_initialized
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
      assert_equal(123, T.unsafe(Addon.addons.first).field)
    end

    def test_loading_addons_initializes_them
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

      queue = Thread::Queue.new
      Addon.load_addons(GlobalState.new, queue)
      error_addon = T.must(Addon.addons.find(&:error?))
      queue.close

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

      begin
        queue = Thread::Queue.new
        Addon.load_addons(GlobalState.new, queue)
        assert_equal(1, Addon.file_watcher_addons.length)
        assert_instance_of(klass, Addon.file_watcher_addons.first)
      ensure
        T.must(queue).close
        Addon.file_watcher_addons.clear
      end
    end

    def test_get_an_addon_by_name
      addon = Addon.get("My Add-on", "0.1.0")
      assert_equal("My Add-on", addon.name)
    end

    def test_raises_if_an_addon_cannot_be_found
      assert_raises(Addon::AddonNotFoundError) do
        Addon.get("Invalid Addon", "0.1.0")
      end
    end

    def test_raises_if_an_addon_version_does_not_match
      assert_raises(Addon::IncompatibleApiError) do
        Addon.get("My Add-on", "> 15.0.0")
      end
    end

    def test_addons_receive_settings
      global_state = GlobalState.new
      global_state.apply_options({
        initializationOptions: {
          addonSettings: {
            "My Add-on" => { something: false },
          },
        },
      })

      outgoing_queue = Thread::Queue.new
      Addon.load_addons(global_state, outgoing_queue)

      addon = Addon.get("My Add-on", "0.1.0")

      assert_equal({ something: false }, T.unsafe(addon).settings)
    ensure
      T.must(outgoing_queue).close
    end

    def test_depend_on_constraints
      assert_raises(Addon::IncompatibleApiError) do
        Addon.depend_on_ruby_lsp!(">= 10.0.0")
      end

      Addon.depend_on_ruby_lsp!(">= 0.18.0", "< 0.30.0")
    end
  end
end
