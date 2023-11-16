# typed: true
# frozen_string_literal: true

require "test_helper"

require "rubocop-minitest"
require "rubocop/minitest/assert_offense"

class UseRegisterWithHandlerMethodTest < Minitest::Test
  include RuboCop::Minitest::AssertOffense

  def setup
    @cop = ::RuboCop::Cop::RubyLsp::UseRegisterWithHandlerMethod.new
  end

  def test_registers_offense_when_use_listener_without_handler
    assert_offense(<<~RUBY)
       class MyListener < Listener
        def initialize(dispatcher)
          super()
          dispatcher.register(
            self,
            :on_string_node_enter,
            ^^^^^^^^^^^^^^^^^^^^^ RubyLsp/UseRegisterWithHandlerMethod: Registered to `on_string_node_enter` without a handler defined.

          )
        end
      end
    RUBY
  end

  def test_registers_offense_when_use_handler_without_listener
    assert_offense(<<~RUBY)
       class MyListener < Listener
        def initialize(dispatcher)
          super()
          dispatcher.register(
            self,
          )
        end

        def on_string_node_enter(node)
        ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ RubyLsp/UseRegisterWithHandlerMethod: Created a handler without registering the associated `on_string_node_enter` event.
        end
      end
    RUBY
  end

  def test_registers_offense_when_both_are_mismatching
    assert_offense(<<~RUBY)
       class MyListener < Listener
        def initialize(dispatcher)
          super()
          dispatcher.register(
            self,
            :on_string_node_enter,
            ^^^^^^^^^^^^^^^^^^^^^ RubyLsp/UseRegisterWithHandlerMethod: Registered to `on_string_node_enter` without a handler defined.
          )
        end

        def on_string_node_leave(node)
        ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ RubyLsp/UseRegisterWithHandlerMethod: Created a handler without registering the associated `on_string_node_leave` event.
        end
      end
    RUBY
  end

  def test_registers_multiple_offenses_for_listeners
    assert_offense(<<~RUBY)
       class MyListener < Listener
        def initialize(dispatcher)
          super()
          dispatcher.register(
            self,
            :on_string_node_enter,
            ^^^^^^^^^^^^^^^^^^^^^ RubyLsp/UseRegisterWithHandlerMethod: Registered to `on_string_node_enter` without a handler defined.
            :on_string_node_leave,
            ^^^^^^^^^^^^^^^^^^^^^ RubyLsp/UseRegisterWithHandlerMethod: Registered to `on_string_node_leave` without a handler defined.
            :on_constant_path_node_enter
            ^^^^^^^^^^^^^^^^^^^^^^^^^^^^ RubyLsp/UseRegisterWithHandlerMethod: Registered to `on_constant_path_node_enter` without a handler defined.
          )
        end
      end
    RUBY
  end

  def test_registers_multiple_offenses_for_handlers
    assert_offense(<<~RUBY)
       class MyListener < Listener
        def initialize(dispatcher)
          super()
          dispatcher.register(
            self,
          )
        end
        def on_string_node_enter(node)
        ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ RubyLsp/UseRegisterWithHandlerMethod: Created a handler without registering the associated `on_string_node_enter` event.
        end
        def on_string_node_leave(node)
        ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ RubyLsp/UseRegisterWithHandlerMethod: Created a handler without registering the associated `on_string_node_leave` event.
        end
        def on_constant_path_node_enter(node)
        ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ RubyLsp/UseRegisterWithHandlerMethod: Created a handler without registering the associated `on_constant_path_node_enter` event.
        end
      end
    RUBY
  end

  def test_does_not_register_offense_when_using_listener_with_handler
    assert_no_offenses(<<~RUBY)
       class MyListener < Listener
        def initialize(dispatcher)
          super()
          dispatcher.register(
            self,
            :on_string_node_enter
          )
        end
        def on_string_node_enter(node)
        end
      end
    RUBY
  end
end
