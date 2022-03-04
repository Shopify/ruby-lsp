# frozen_string_literal: true

require "language_server-protocol"

require_relative "handler"

module Ruby
  module Lsp
    module Cli
      def self.start(_argv)
        handler = Ruby::Lsp::Handler.new

        handler.config do
          on("initialize") do
            respond_with_capabilities
            nil
          end

          on("shutdown") do
            nil
          end
        end

        handler.start
      end
    end
  end
end
