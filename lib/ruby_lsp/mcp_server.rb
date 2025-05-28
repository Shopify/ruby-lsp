# typed: strict
# frozen_string_literal: true

require "ruby_lsp/mcp/tool"

module RubyLsp
  class MCPServer
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
            code: JsonRpcHandler::ErrorCode::InternalError,
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
          code: JsonRpcHandler::ErrorCode::InternalError,
          message: "Internal error",
          data: e.message,
        },
      }.to_json
    end

    #: (String) -> String?
    def process_jsonrpc_request(json)
      puts "[MCP] Processing request: #{json.inspect}"

      JsonRpcHandler.handle_json(json) do |method_name|
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
              contents = tool_class.new(@index).call(params[:arguments] || {})
              generate_response(contents)
            end
          }
        end
      end
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
