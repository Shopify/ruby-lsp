# typed: strict
# frozen_string_literal: true

module RubyLsp
  module Listeners
    class RailsApp
      extend T::Sig

      sig { returns(T::Boolean) }
      attr_reader :rails_app

      sig { params(dispatcher: Prism::Dispatcher).void }
      def initialize(dispatcher)
        @rails_app = T.let(false, T::Boolean)
        dispatcher.register(self, :on_class_node_enter)
      end

      sig { params(node: Prism::ClassNode).void }
      def on_class_node_enter(node)
        superclass = node.superclass
        case superclass
        when Prism::ConstantPathNode
          @rails_app = true if superclass.full_name == "Rails::Application"
        end
      end
    end
  end
end
