# typed: strict
# frozen_string_literal: true

require "prism"

module RubyIndexer
  module PrismDispatcherDynamicRegistrationPatch
    #: (Object listener, Symbol events) -> void
    def register(listener, *events)
      events = listener.public_methods.grep(/^on_.+_(?:enter|leave)$/) if events.empty?

      super
    end
  end

  Prism::Dispatcher.prepend(PrismDispatcherDynamicRegistrationPatch)
end
