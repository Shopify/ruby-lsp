# typed: strict
# frozen_string_literal: true

require "net/http"
require "uri"
require "socket"
require "json"
require "securerandom"

module RubyLsp
  class MCPServer
    def initialize(port = 4444)
      @port = port
      @server = TCPServer.new("0.0.0.0", @port)
      @running = false
      @sessions = {}
    end

    def start
      @running = true
      puts "[MCP] Server started on port #{@port}"

      while @running
        Thread.start(@server.accept) do |socket|
          handle_connection(socket)
        end
      end
    end

    def stop
      @running = false
      @server.close
    end

    private

    def handle_connection(socket)
      request_line = socket.gets
      return unless request_line

      method, path, _ = request_line.split(" ")
      headers = {}
      while (line = socket.gets) && (line != "\r\n")
        key, value = line.split(": ", 2)
        headers[key] = value.strip
      end

      puts "[MCP] Received headers: #{headers.inspect}"
      puts "[MCP] Received method: #{method}"
      puts "[MCP] Received path: #{path}"
      if method == "GET"
        handle_sse_connection(socket)
      elsif method == "POST"
        content_length = headers["Content-Length"].to_i
        body = socket.read(content_length)
        handle_post_request(socket, body)
      else
        puts "[MCP] Received unknown method: #{method}"
        respond(socket, 404, "Not Found")
      end
    rescue => e
      puts "[MCP] Connection error: #{e.message}"
      puts e.backtrace.join("\n")
    ensure
      socket.close unless socket.closed?
    end

    def handle_sse_connection(socket)
      session_id = SecureRandom.uuid
      @sessions[session_id] = socket

      socket.write("HTTP/1.1 200 OK\r\n")
      socket.write("Content-Type: text/event-stream\r\n")
      socket.write("Cache-Control: no-cache\r\n")
      socket.write("Connection: keep-alive\r\n")
      socket.write("\r\n")
      socket.flush

      # Immediately send the required endpoint event
      send_sse_event(socket, "endpoint", "/sse/messages?session_id=#{session_id}")

      # Keep-alive loop
      loop do
        sleep(15)
        socket.write(": ping - #{Time.now}\n\n")
        socket.flush
      end
    rescue IOError, Errno::EPIPE
      puts "[MCP] SSE client disconnected"
    ensure
      @sessions.delete(session_id)
      socket.close unless socket.closed?
    end

    def handle_post_request(socket, body)
      if body.nil? || body.strip.empty?
        # MCP Inspector expects a simple empty JSON response for initial empty POST requests
        respond(socket, 200, "{}")
        return
      end

      request = JSON.parse(body, symbolize_names: true)

      case request[:method]
      when "initialize"
        respond(socket, 200, {
          jsonrpc: "2.0",
          id: request[:id],
          result: {
            protocolVersion: "2024-11-05",
            capabilities: {
              tools: { listChanged: true },
              resources: { listChanged: true, subscribe: true },
              prompts: { listChanged: true },
              logging: true,
              roots: { listChanged: true },
              sampling: true,
            },
            serverInfo: {
              name: "ruby-lsp-mcp-server",
              version: "0.1.0",
            },
            offerings: [],
            tools: [],
          },
        }.to_json)
      when "class/getAncestors"
        class_name = request.dig(:params, :className)
        ancestors = fetch_class_ancestors(class_name)
        respond(socket, 200, {
          jsonrpc: "2.0",
          id: request[:id],
          result: { ancestors: ancestors },
        }.to_json)
      else
        respond(socket, 200, {
          jsonrpc: "2.0",
          id: request[:id],
          error: { code: -32601, message: "Method not found" },
        }.to_json)
      end
    rescue JSON::ParserError => e
      respond(socket, 400, { error: "Invalid JSON: #{e.message}" }.to_json)
    rescue => e
      respond(socket, 500, { error: e.message }.to_json)
    end

    def respond(socket, status, body)
      socket.write("HTTP/1.1 #{status}\r\n")
      socket.write("Content-Type: application/json\r\n")
      socket.write("Content-Length: #{body.bytesize}\r\n")
      socket.write("\r\n")
      socket.write(body)
    end

    def send_sse_event(socket, event, data)
      socket.write("event: #{event}\n")
      socket.write("data: #{data}\n\n")
      socket.flush
    end

    def fetch_class_ancestors(class_name)
      klass = Object.const_get(class_name)
      klass.ancestors.map(&:to_s)
    rescue NameError
      []
    end
  end
end
