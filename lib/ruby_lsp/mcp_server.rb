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
        headers[key.downcase] = value.strip
      end

      puts "[MCP] Received headers: #{headers.inspect}"
      puts "[MCP] Received method: #{method}"
      puts "[MCP] Received path: #{path}"

      if method == "GET"
        handle_sse_connection(socket)
      elsif method == "POST"
        content_length = headers["content-length"].to_i
        body = read_request_body(socket, content_length)
        handle_post_request(socket, body)
      else
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

      puts "[MCP] Established SSE connection with session_id=#{session_id}"

      socket.write("HTTP/1.1 200 OK\r\n")
      socket.write("Content-Type: text/event-stream\r\n")
      socket.write("Cache-Control: no-cache\r\n")
      socket.write("Connection: keep-alive\r\n")
      socket.write("\r\n")
      socket.flush

      endpoint_url = "/messages"
      puts "[MCP] Sending endpoint event: #{endpoint_url}"
      send_sse_event(socket, "endpoint", endpoint_url)

      loop do
        sleep(15)
        socket.write(": ping - #{Time.now}\n\n")
        socket.flush
        puts "[MCP] Sent SSE keep-alive ping for session_id=#{session_id}"
      end
    rescue IOError, Errno::EPIPE => e
      puts "[MCP] SSE client disconnected: #{e.message}"
    ensure
      @sessions.delete(session_id)
      socket.close unless socket.closed?
      puts "[MCP] Closed SSE connection for session_id=#{session_id}"
    end

    def handle_post_request(socket, body)
      if body.nil? || body.strip.empty?
        puts "[MCP] Received empty POST request body, responding with empty JSON"
        respond(socket, 200, "{}")
        return
      end

      request = JSON.parse(body, symbolize_names: true)
      puts "[MCP] Parsed JSON-RPC request: #{request.inspect}"

      case request[:method]
      when "initialize"
        puts "[MCP] Handling initialize request"
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
        puts "[MCP] Sent initialize response"
      else
        puts "[MCP] Received unknown method: #{request[:method]}"
        respond(socket, 200, {
          jsonrpc: "2.0",
          id: request[:id],
          error: { code: -32601, message: "Method not found" },
        }.to_json)
        puts "[MCP] Sent method not found error response"
      end
    rescue JSON::ParserError => e
      puts "[MCP] JSON parsing error: #{e.message}"
      respond(socket, 400, { error: "Invalid JSON: #{e.message}" }.to_json)
    rescue => e
      puts "[MCP] Internal server error: #{e.message}"
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

    def read_request_body(socket, content_length)
      body = +""
      remaining = content_length

      while remaining > 0
        chunk = socket.readpartial(remaining)
        body << chunk
        remaining -= chunk.bytesize
      end

      body
    rescue EOFError => e
      puts "[MCP] Error reading request body: #{e.message}"
      ""
    end
  end
end
