# typed: true
# frozen_string_literal: true

require "test_helper"

module RubyLsp
  class AddonTest < Minitest::Test
    def setup
      @addon = Class.new(Addon) do
        attr_reader :activated

        def activate
          @activated = true
        end

        def name
          "My Addon"
        end
      end
    end

    def teardown
      Addon.addons.clear
    end

    def test_registering_an_addon_invokes_activate_on_initialized
      message_queue = Thread::Queue.new
      Executor.new(RubyLsp::Store.new, message_queue).execute({ method: "initialized" })

      addon_instance = T.must(Addon.addons.find { |addon| addon.is_a?(@addon) })
      assert_predicate(addon_instance, :activated)
    ensure
      T.must(message_queue).close
    end

    def test_addons_are_automatically_tracked
      assert(
        Addon.addons.any? { |addon| addon.is_a?(@addon) },
        "Expected addon to be automatically tracked",
      )
    end

    def test_load_addons_returns_errors
      Class.new(Addon) do
        def activate
          raise StandardError, "Failed to activate"
        end

        def name
          "My addon"
        end
      end

      Addon.load_addons
      error_addon = T.must(Addon.addons.find(&:error?))

      assert_predicate(error_addon, :error?)
      assert_equal(<<~MESSAGE, error_addon.formatted_errors)
        My addon:
          Failed to activate
      MESSAGE
    end
  end
end
