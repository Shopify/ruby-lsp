# typed: true
# frozen_string_literal: true

require "json"
require "ruby_lsp/addon/process_server"

module RubyLsp
  class Addon
    class FakeProcessServer < ProcessServer
      def generate_initialize_response
        JSON.dump({ result: { initialized: true } })
      end

      def execute(request, params)
        case request
        when "echo"
          { result: { echo_result: params[:message] } }
        when "shutdown"
          @running = false
          { result: {} }
        else
          VOID
        end
      end
    end
  end
end

RubyLsp::Addon::FakeProcessServer.new.start
