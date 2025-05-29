# typed: strict
# frozen_string_literal: true

require "ruby_lsp/mcp/tool"

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
      port_file = File.join(lsp_dir, "mcp-port")
      File.write(port_file, @port.to_s)

      # Create WEBrick server
      @server = WEBrick::HTTPServer.new(
        Port: @port,
        BindAddress: "127.0.0.1",
        Logger: WEBrick::Log.new(File.join(lsp_dir, "mcp-webrick.log")),
        AccessLog: [],
      ) #: WEBrick::HTTPServer

      # Mount the MCP handler
      @server.mount_proc("/mcp") do |req, res|
        handle_mcp_request(req, res)
      end

      @running = false #: T::Boolean
      @global_state = global_state #: GlobalState
      @index = global_state.index #: RubyIndexer::Index
    end

    #: -> void
    def start
      puts "[MCP] Server started on TCP port #{@port}"
      Thread.new do
        @server.start
      end
    end

    #: -> void
    def stop
      puts "[MCP] Stopping server"
      @server.shutdown
    ensure
      # Clean up port file
      lsp_dir = File.join(@workspace_path, ".ruby-lsp")
      port_file = File.join(lsp_dir, "mcp-port")
      File.delete(port_file) if File.exist?(port_file)

      # Clean up log file
      log_file = File.join(lsp_dir, "mcp-webrick.log")
      File.delete(log_file) if File.exist?(log_file)
    end

    private

    #: (WEBrick::HTTPRequest, WEBrick::HTTPResponse) -> void
    def handle_mcp_request(request, response)
      body = request.body || ""

      puts "[MCP] Received request: #{body}"

      result = process_jsonrpc_request(body)

      if result.nil?
        response.status = 500
        response.body = {
          jsonrpc: "2.0",
          id: nil,
          error: {
            code: ErrorCode::INTERNAL_ERROR,
            message: "Internal error",
            data: "No response from the server",
          },
        }.to_json
      else
        response.status = 200
        response.content_type = "application/json"
        response.body = result
      end

      puts "[MCP] Sent response: #{response.body}"
    rescue => e
      puts "[MCP] Error processing request: #{e.message}"
      puts e.backtrace&.join("\n")

      response.status = 500
      response.body = {
        jsonrpc: "2.0",
        id: nil,
        error: {
          code: ErrorCode::INTERNAL_ERROR,
          message: "Internal error",
          data: e.message,
        },
      }.to_json
    end

    #: (String) -> String?
    def process_jsonrpc_request(json)
      puts "[MCP] Processing request: #{json.inspect}"

      handle_json_rpc(json) do |method_name|
        case method_name
        when "initialize"
          ->(_) do
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
          end
        when "initialized", "notifications/initialized"
          ->(_) do
            {}
          end
        when "tools/list"
          ->(_) do
            {
              tools: RubyLsp::MCP::Tool.tools.map do |tool_name, tool_class|
                {
                  name: tool_name,
                  description: tool_class.description.dump, # avoid newlines in the description
                  inputSchema: tool_class.input_schema,
                }
              end,
            }
          end
        when "tools/call"
          ->(params) {
            puts "[MCP] Received tools/call request: #{params.inspect}"
            tool_name = params[:name]
            tool_class = RubyLsp::MCP::Tool.get(tool_name)

            if tool_class
              arguments = params[:arguments] || {}
              contents = tool_class.new(@index).call(arguments)
              generate_response(contents)
            else
              generate_response([])
            end
          }
        end
      end
    end

    #: (String) { (String) -> Proc? } -> String?
    def handle_json_rpc(json, &block)
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

      # Get method handler from block
      handler = block.call(method_name)

      unless handler
        return generate_error_response(
          request_id,
          ErrorCode::METHOD_NOT_FOUND,
          "Method not found",
          "Method '#{method_name}' not found",
        )
      end

      # Call the handler
      begin
        result = handler.call(params)
        generate_success_response(request_id, result)
      rescue => e
        generate_error_response(request_id, ErrorCode::INTERNAL_ERROR, "Internal error", e.message)
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
