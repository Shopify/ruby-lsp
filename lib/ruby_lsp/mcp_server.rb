# typed: strict
# frozen_string_literal: true

require "ruby_lsp/mcp/tool"
require "socket"

module RubyLsp
  class MCPServer
    # JSON-RPC 2.0 Error Codes
    module ErrorCode
      PARSE_ERROR = -32700
      INVALID_REQUEST = -32600
      METHOD_NOT_FOUND = -32601
      INVALID_PARAMS = -32602
      INTERNAL_ERROR = -32603
    end

    class << self
      # Find an available TCP port
      #: -> Integer
      def find_available_port
        server = TCPServer.new("127.0.0.1", 0)
        port = server.addr[1]
        server.close
        port
      end
    end

    #: (GlobalState) -> void
    def initialize(global_state)
      @workspace_path = global_state.workspace_path #: String
      @port = self.class.find_available_port #: Integer

      # Create .ruby-lsp directory if it doesn't exist
      lsp_dir = File.join(@workspace_path, ".ruby-lsp")
      FileUtils.mkdir_p(lsp_dir)

      # Write port to file
      @port_file = File.join(lsp_dir, "mcp-port") #: String
      File.write(@port_file, @port.to_s)

      # Create TCP server
      @server = TCPServer.new("127.0.0.1", @port) #: TCPServer
      @server_thread = nil #: Thread?

      @running = false #: T::Boolean
      @global_state = global_state #: GlobalState
      @index = global_state.index #: RubyIndexer::Index
    end

    #: -> void
    def start
      puts "[MCP] Server started on port #{@port}"
      @running = true

      @server_thread = Thread.new do
        while @running
          begin
            # Accept incoming connections
            client = @server.accept

            # Handle each client in a separate thread
            Thread.new(client) do |client_socket|
              handle_client(client_socket)
            end
          rescue => e
            puts "[MCP] Error accepting connection: #{e.message}" if @running
          end
        end
      end
    end

    #: -> void
    def stop
      puts "[MCP] Server stopping"
      @running = false
      @server.close
      @server_thread&.join
    ensure
      File.delete(@port_file) if File.exist?(@port_file)
    end

    private

    #: (TCPSocket) -> void
    def handle_client(client_socket)
      # Read JSON-RPC request from client
      request_line = client_socket.gets
      return unless request_line

      request_line = request_line.strip

      # Process the JSON-RPC request
      response = process_jsonrpc_request(request_line)

      if response
        client_socket.puts(response)
      end
    rescue => e
      puts "[MCP] Client error: #{e.message}"

      # Send error response
      error_response = generate_error_response(nil, ErrorCode::INTERNAL_ERROR, "Internal error", e.message)
      client_socket.puts(error_response)
    ensure
      client_socket.close
    end

    #: (String) -> String?
    def process_jsonrpc_request(json)
      # Parse JSON
      begin
        request = JSON.parse(json, symbolize_names: true)
      rescue JSON::ParserError
        return generate_error_response(nil, ErrorCode::PARSE_ERROR, "Parse error", "Invalid JSON")
      end

      # Validate JSON-RPC 2.0 format
      unless request.is_a?(Hash) && request[:jsonrpc] == "2.0"
        return generate_error_response(
          request[:id],
          ErrorCode::INVALID_REQUEST,
          "Invalid Request",
          "Not a valid JSON-RPC 2.0 request",
        )
      end

      method_name = request[:method]
      params = request[:params] || {}
      request_id = request[:id]

      begin
        result = process_request(method_name, params)

        if result
          generate_success_response(request_id, result)
        else
          generate_error_response(
            request_id,
            ErrorCode::METHOD_NOT_FOUND,
            "Method not found",
            "Method '#{method_name}' not found",
          )
        end
      rescue => e
        generate_error_response(request_id, ErrorCode::INTERNAL_ERROR, "Internal error", e.message)
      end
    end

    #: (String, Hash[Symbol, untyped]) -> Hash[Symbol, untyped]?
    def process_request(method_name, params)
      case method_name
      when "initialize"
        {
          protocolVersion: "2024-11-05",
          capabilities: {
            tools: { list_changed: false },
          },
          serverInfo: {
            name: "ruby-lsp-mcp-server",
            version: "0.1.0",
          },
        }
      when "initialized", "notifications/initialized"
        {}
      when "tools/list"
        {
          tools: RubyLsp::MCP::Tool.tools.map do |tool_name, tool_class|
            {
              name: tool_name,
              description: tool_class.description,
              inputSchema: tool_class.input_schema,
            }
          end,
        }
      when "tools/call"
        tool_name = params[:name]
        tool_class = RubyLsp::MCP::Tool.get(tool_name)

        if tool_class
          arguments = params[:arguments] || {}
          contents = tool_class.new(@index, arguments).perform
          generate_response(contents)
        else
          generate_response([])
        end
      end
    end

    #: (Integer?, untyped) -> String
    def generate_success_response(id, result)
      {
        jsonrpc: "2.0",
        id: id,
        result: result,
      }.to_json
    end

    #: (Integer?, Integer, String, String) -> String
    def generate_error_response(id, code, message, data)
      {
        jsonrpc: "2.0",
        id: id,
        error: {
          code: code,
          message: message,
          data: data,
        },
      }.to_json
    end

    #: (Array[Hash[Symbol, untyped]]) -> Hash[Symbol, untyped]
    def generate_response(contents)
      if contents.empty?
        {
          content: [
            {
              type: "text",
              text: "No results found",
            },
          ],
        }
      else
        {
          content: contents,
        }
      end
    end
  end
end
