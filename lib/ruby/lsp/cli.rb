# frozen_string_literal: true

require "language_server-protocol"

require_relative "handler"

module Ruby
  module Lsp
    module Cli
      def self.start(_argv)
        handler = Ruby::Lsp::Handler.new

        handler.config do
          on("initialize") { respond_with_capabilities }
          on("shutdown") { shutdown }
        end

        handler.start
      end
    end
  end
end
