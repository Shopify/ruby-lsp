# typed: true
# frozen_string_literal: true

require "test_helper"

module RubyLsp
  class AddonTest < Minitest::Test
    def setup
      @addon = Class.new(Addon) do
        attr_reader :activated, :field

        def initialize
          @field = 123
          super
        end

        def activate(message_queue)
          @activated = true
        end

        def name
          "My Addon"
        end
      end

      @message_queue = Thread::Queue.new
      Addon.load_addons(@message_queue)
    end

    def teardown
      RubyLsp::Addon.addon_classes.clear
      RubyLsp::Addon.addons.clear
      @message_queue.close
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
        "Expected addon to be automatically tracked",
      )
    end

    def test_load_addons_returns_errors
      Class.new(Addon) do
        def activate(message_queue)
          raise StandardError, "Failed to activate"
        end

        def name
          "My addon"
        end
      end

      queue = Thread::Queue.new
      Addon.load_addons(queue)
      error_addon = T.must(Addon.addons.find(&:error?))
      queue.close

      assert_predicate(error_addon, :error?)
      assert_equal(<<~MESSAGE, error_addon.formatted_errors)
        My addon:
          Failed to activate
      MESSAGE
    end

    def test_automatically_identifies_file_watcher_addons
      klass = Class.new(::RubyLsp::Addon) do
        def activate(message_queue); end
        def deactivate; end

        def workspace_did_change_watched_files(changes); end
      end

      begin
        queue = Thread::Queue.new
        Addon.load_addons(queue)
        assert_equal(1, Addon.file_watcher_addons.length)
        assert_instance_of(klass, Addon.file_watcher_addons.first)
      ensure
        T.must(queue).close
        Addon.file_watcher_addons.clear
      end
    end
  end
end
