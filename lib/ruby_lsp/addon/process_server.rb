# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"

module RubyLsp
  class Addon
    class ProcessServer
      extend T::Sig
      extend T::Generic

      abstract!

      VOID = Object.new

      sig { void }
      def initialize
        $stdin.sync = true
        $stdout.sync = true
        $stdin.binmode
        $stdout.binmode
        @running = T.let(true, T.nilable(T::Boolean))
      end

      sig { void }
      def start
        initialize_result = generate_initialize_response
        $stdout.write("Content-Length: #{initialize_result.length}\r\n\r\n#{initialize_result}")

        while @running
          headers = $stdin.gets("\r\n\r\n")
          json = $stdin.read(headers[/Content-Length: (\d+)/i, 1].to_i)

          request = JSON.parse(json, symbolize_names: true)
          response = execute(request.fetch(:method), request[:params])
          next if response == VOID

          json_response = response.to_json
          $stdout.write("Content-Length: #{json_response.length}\r\n\r\n#{json_response}")
        end
      end

      sig { abstract.returns(String) }
      def generate_initialize_response; end

      sig { abstract.params(request: String, params: T.untyped).returns(T.untyped) }
      def execute(request, params); end
    end
  end
end
