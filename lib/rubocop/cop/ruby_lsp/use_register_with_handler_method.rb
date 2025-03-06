# typed: strict
# frozen_string_literal: true

require "rubocop"
require "sorbet-runtime"

module RuboCop
  module Cop
    module RubyLsp
      # Avoid using register without handler method, or handler without register.
      #
      # @example
      # # Register without handler method.
      #
      # # bad
      # class MyListener
      #   def initialize(dispatcher)
      #     dispatcher.register(
      #       self,
      #       :on_string_node_enter,
      #     )
      #   end
      # end
      #
      # # good
      # class MyListener
      #   def initialize(dispatcher)
      #     dispatcher.register(
      #       self,
      #       :on_string_node_enter,
      #     )
      #   end
      #
      #   def on_string_node_enter(node)
      #   end
      # end
      #
      # @example
      # # Handler method without register.
      #
      # # bad
      # class MyListener
      #   def initialize(dispatcher)
      #     dispatcher.register(
      #       self,
      #     )
      #   end
      #
      #   def on_string_node_enter(node)
      #   end
      # end
      #
      # # good
      # class MyListener
      #   def initialize(dispatcher)
      #     dispatcher.register(
      #       self,
      #       :on_string_node_enter,
      #     )
      #   end
      #
      #   def on_string_node_enter(node)
      #   end
      # end
      class UseRegisterWithHandlerMethod < RuboCop::Cop::Base
        MSG_MISSING_HANDLER = "Registered to `%{listener}` without a handler defined."
        MSG_MISSING_LISTENER = "Created a handler without registering the associated `%{listener}` event."

        def_node_search(
          :find_all_listeners,
          "(send
            (_ :dispatcher) :register
            (self)
            $(sym _)+)",
        )

        def_node_search(
          :find_all_handlers,
          "$(def [_ #valid_event_name?] (args (arg _)) ...)",
        )

        def on_new_investigation
          return if processed_source.blank?

          listeners = find_all_listeners(processed_source.ast).flat_map { |listener| listener }
          handlers = find_all_handlers(processed_source.ast).flat_map { |handler| handler }

          add_offense_to_listeners_without_handler(listeners, handlers)
          add_offense_handlers_without_listener(listeners, handlers)
        end

        private

        #: (Symbol event_name) -> bool
        def valid_event_name?(event_name)
          /^on_.*(node_enter|node_leave)$/.match?(event_name)
        end

        #: (Array[RuboCop::AST::SymbolNode] listeners, Array[RuboCop::AST::DefNode] handlers) -> void
        def add_offense_to_listeners_without_handler(listeners, handlers)
          return if listeners.none?

          listeners
            .filter { |node| handlers.map(&:method_name).none?(node.value) }
            .each { |node| add_offense(node, message: format(MSG_MISSING_HANDLER, listener: node.value)) }
        end

        #: (Array[RuboCop::AST::SymbolNode] listeners, Array[RuboCop::AST::DefNode] handlers) -> void
        def add_offense_handlers_without_listener(listeners, handlers)
          return if handlers.none?

          handlers
            .filter { |node| listeners.map(&:value).none?(node.method_name) }
            .each { |node| add_offense(node, message: format(MSG_MISSING_LISTENER, listener: node.method_name)) }
        end
      end
    end
  end
end
