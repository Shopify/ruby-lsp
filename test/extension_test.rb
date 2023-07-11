# typed: true
# frozen_string_literal: true

require "test_helper"

module RubyLsp
  class ExtensionTest < Minitest::Test
    def setup
      @extension = Class.new(Extension) do
        attr_reader :activated

        def activate
          @activated = true
        end

        def name
          "My extension"
        end
      end
    end

    def teardown
      Extension.extensions.clear
    end

    def test_registering_an_extension_invokes_activate_on_initialized
      message_queue = Thread::Queue.new
      Executor.new(RubyLsp::Store.new, message_queue).execute({ method: "initialized" })

      extension_instance = T.must(Extension.extensions.find { |ext| ext.is_a?(@extension) })
      assert_predicate(extension_instance, :activated)
    ensure
      T.must(message_queue).close
    end

    def test_extensions_are_automatically_tracked
      assert(
        Extension.extensions.any? { |ext| ext.is_a?(@extension) },
        "Expected extension to be automatically tracked",
      )
    end

    def test_load_extensions_returns_errors
      Class.new(Extension) do
        def activate
          raise StandardError, "Failed to activate"
        end

        def name
          "My extension"
        end
      end

      Extension.load_extensions({})
      error_extension = T.must(Extension.extensions.find(&:error?))

      assert_predicate(error_extension, :error?)
      assert_equal(<<~MESSAGE, error_extension.formatted_errors)
        My extension:
          Failed to activate
      MESSAGE
    end

    def test_load_extensions_does_not_activated_disabled_extensions
      Class.new(Extension) do
        def activate
          RubyLsp::Requests::Hover.add_listener(Class.new(RubyLsp::Listener))
        end

        def name
          "My extension"
        end
      end

      Extension.load_extensions({ "My extension" => { activated: false } })
      assert_empty(RubyLsp::Requests::Hover.listeners)
    end
  end
end
