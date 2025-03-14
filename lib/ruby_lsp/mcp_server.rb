# typed: strict
# frozen_string_literal: true

require "socket"
require "json"
require "sorbet-runtime"

module RubyLsp
  class MCPServer
    extend T::Sig

    sig { params(global_state: GlobalState).void }
    def initialize(global_state)
      @socket_name = T.let(File.basename(global_state.workspace_path), String)
      @socket_path = T.let(File.join("/tmp/ruby-mcp-socket", @socket_name), String)
      @server = T.let(Socket.unix_server_socket(@socket_path), Socket)
      @running = T.let(false, T::Boolean)
      @global_state = T.let(global_state, GlobalState)
      @index = T.let(global_state.index, RubyIndexer::Index)
    end

    sig { void }
    def start
      @running = true
      puts "[MCP] Server started on socket #{@socket_path}"

      while @running
        Thread.start(@server.accept) do |socket|
          handle_connection(socket.first)
        end
      end
    end

    sig { void }
    def stop
      @running = false
      @server.close
    end

    private

    sig { params(socket: Socket).void }
    def handle_connection(socket)
      request_line = socket.gets
      return unless request_line

      method, path, _ = request_line.split(" ")
      headers = {}
      while (line = socket.gets) && (line != "\r\n")
        key, value = line.split(": ", 2)
        headers[key.downcase] = value.strip if key && value
      end

      puts "[MCP] Received: #{method} #{path}"

      if method == "POST" && path == "/mcp"
        content_length = headers["content-length"].to_i
        body = read_request_body(socket, content_length)
        handle_mcp_request(socket, body)
      else
        # Proper JSON-RPC error for unknown endpoint
        error_response = {
          jsonrpc: "2.0",
          id: 0, # Use a default ID for requests without an ID
          error: {
            code: -32601,
            message: "Method not found",
            data: "Endpoint not found: #{path}",
          },
        }
        respond(socket, 404, error_response.to_json)
      end
    rescue => e
      puts "[MCP] Connection error: #{e.message}"
      puts e.backtrace.join("\n") if e.backtrace
    ensure
      socket.close unless socket.closed?
    end

    sig { params(socket: Socket, body: String).void }
    def handle_mcp_request(socket, body)
      if body.strip.empty?
        puts "[MCP] Received empty MCP request body"
        error_response = {
          jsonrpc: "2.0",
          id: 0, # Use a default ID since we couldn't parse one
          error: {
            code: -32700,
            message: "Parse error",
            data: "Empty request body",
          },
        }
        respond(socket, 400, error_response.to_json)
        return
      end

      puts "[MCP] Received request: #{body}"

      begin
        request = JSON.parse(body, symbolize_names: true)
        response = process_jsonrpc_request(request)
        respond(socket, 200, response.to_json)
        puts "[MCP] Sent response: #{response.inspect}"
      rescue JSON::ParserError => e
        puts "[MCP] JSON parsing error: #{e.message}"
        error_response = {
          jsonrpc: "2.0",
          id: 0, # Use a default ID since we couldn't parse one
          error: {
            code: -32700,
            message: "Parse error",
            data: e.message,
          },
        }
        respond(socket, 400, error_response.to_json)
      rescue => e
        puts "[MCP] Internal error: #{e.message}"
        error_response = {
          jsonrpc: "2.0",
          id: request ? request[:id] || 0 : 0,
          error: {
            code: -32603,
            message: "Internal error",
            data: e.message,
          },
        }
        respond(socket, 500, error_response.to_json)
      end
    end

    sig { params(request: T::Hash[Symbol, T.untyped]).returns(T::Hash[Symbol, T.untyped]) }
    def process_jsonrpc_request(request)
      puts "[MCP] Processing request: #{request.inspect}"
      request_id = request[:id] || 0

      case request[:method]
      when "initialize"
        puts "[MCP] Processing initialize request"
        {
          jsonrpc: "2.0",
          id: request_id,
          result: {
            protocolVersion: "2024-11-05",
            capabilities: {
              resources: { listChanged: true, subscribe: true },
            },
            serverInfo: {
              name: "ruby-lsp-mcp-server",
              version: "0.1.0",
            },
          },
        }
      when "initialized", "notifications/initialized"
        puts "[MCP] Received initialized notification"
        # Return a proper JSON-RPC response even for notifications
        {
          jsonrpc: "2.0",
          id: request_id,
          result: {}, # Empty result for notifications
        }
      when "resources/list"
        puts "[MCP] Received resources/list request"

        resources = @index.instance_variable_get(:@entries).values.flatten.select do |entry|
          entry.is_a?(RubyIndexer::Entry::Class)
        end.map do |entry|
          {
            uri: "ruby-index://class/#{entry.name}",
            name: "Class: #{entry.name}",
            mimeType: "text/plain",
          }
        end

        {
          jsonrpc: "2.0",
          id: request_id,
          result: { resources: resources },
        }
      else
        puts "[MCP] Unknown method: #{request[:method]}"
        {
          jsonrpc: "2.0",
          id: request_id,
          error: {
            code: -32601,
            message: "Method not found",
            data: "Method not supported: #{request[:method]}",
          },
        }
      end
    end

    sig { params(socket: Socket, status: Integer, body: String).void }
    def respond(socket, status, body)
      socket.write("HTTP/1.1 #{status}\r\n")
      socket.write("Content-Type: application/json\r\n")
      socket.write("Content-Length: #{body.bytesize}\r\n")
      socket.write("\r\n")
      socket.write(body)
    end

    sig { params(socket: Socket, content_length: Integer).returns(String) }
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
