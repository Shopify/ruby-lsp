# typed: strict
# frozen_string_literal: true

require "socket"
require "json"
require "sorbet-runtime"
require "json_rpc_handler"
require "ruby_lsp/requests/support/common"

module RubyLsp
  class MCPServer
    extend T::Sig
    include Requests::Support::Common

    SOCKET_FOLDER = "/tmp/ruby-mcp-socket"

    sig { params(global_state: GlobalState).void }
    def initialize(global_state)
      @socket_name = T.let(File.basename(global_state.workspace_path), String)
      unless Dir.exist?(SOCKET_FOLDER)
        Dir.mkdir(SOCKET_FOLDER)
      end
      @socket_path = T.let(File.join(SOCKET_FOLDER, @socket_name), String)
      if File.exist?(@socket_path)
        File.delete(@socket_path)
      end
      @socket = T.let(Socket.unix_server_socket(@socket_path), Socket)
      @running = T.let(false, T::Boolean)
      @global_state = T.let(global_state, GlobalState)
      @index = T.let(global_state.index, RubyIndexer::Index)
    end

    sig { void }
    def start
      @running = true
      puts "[MCP] Server started on socket #{@socket_path}"

      while @running
        puts "[MCP] Sleeping for 0.1 seconds"
        sleep(0.1)
        puts "[MCP] Waking up and checking for connections"
        begin
          # Use IO.select to check if the socket is ready
          ready = begin
            IO.select([@socket], nil, nil, 0)
          rescue
            nil
          end

          if ready
            begin
              client_socket = @socket.accept_nonblock
              Thread.start(client_socket) do |socket, _|
                handle_connection(socket)
              rescue => e
                puts "[MCP] Error in connection thread: #{e.message}"
                puts e.backtrace&.join("\n")
              ensure
                socket.close
              end
            rescue IO::WaitReadable, Errno::EAGAIN
              # No client trying to connect, just retry
              sleep(0.1)
            end
          end
        rescue => e
          puts "[MCP] Error in accept loop: #{e.message}"
          puts e.backtrace&.join("\n")
          # Add a small sleep to avoid tight loop in case of persistent errors
          sleep(1)
        end
      end
    end

    sig { void }
    def stop
      puts "[MCP] Stopping server"
      @running = false
      @socket.close
    end

    private

    sig { params(socket: Socket).void }
    def handle_connection(socket)
      # Use select with timeout before gets
      readable, = IO.select([socket], nil, nil, 5)
      unless readable
        puts "[MCP] Timeout waiting for request line"
        return
      end
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
      puts e.backtrace&.join("\n")
    ensure
      socket.close
    end

    sig { params(socket: Socket, body: String).void }
    def handle_mcp_request(socket, body)
      puts "[MCP] Received request: #{body}"

      response = process_jsonrpc_request(body)
      respond(socket, 200, response)
      puts "[MCP] Sent response: #{response.inspect}"
    end

    sig { params(json: String).returns(String) }
    def process_jsonrpc_request(json)
      puts "[MCP] Processing request: #{json.inspect}"

      JsonRpcHandler.handle_json(json) do |method_name|
        case method_name
        when "initialize"
          puts "[MCP] Processing initialize request"
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
          puts "[MCP] Received initialized notification"
          ->(_) do
            {}
          end
        when "tools/list"
          puts "[MCP] Received tools/list request"
          ->(_) do
            {
              tools: [
                {
                  name: "all_classes_entries",
                  description: "Show all the indexed classes entries in the current project",
                  inputSchema: {
                    type: "object",
                    properties: {},
                  },
                },
                {
                  name: "constant_details",
                  description: <<~DESCRIPTION,
                    Show the details of the given class/module, including:
                    - Comments
                    - Definition location
                  DESCRIPTION
                  inputSchema: {
                    type: "object",
                    properties: {
                      fully_qualified_name: {
                        type: "string",
                      },
                    },
                    required: ["fully_qualified_name"],
                  },
                },
                {
                  name: "class_details",
                  description: <<~DESCRIPTION,
                    Show the details of the given class, including:
                    - Methods
                    - Ancestors
                  DESCRIPTION
                  inputSchema: {
                    type: "object",
                    properties: {
                      class_name: {
                        type: "string",
                      },
                    },
                    required: ["class_name"],
                  },
                },
              ],
            }
          end
        when "tools/call"
          puts "[MCP] Received tools/call request"
          ->(params) {
            case params[:name]
            when "all_classes_entries"
              puts "[MCP] Received all_classes tool request"
              {
                content: @index.instance_variable_get(:@entries).values.flatten.select do |entry|
                  entry.is_a?(RubyIndexer::Entry::Class)
                end.map do |entry|
                  {
                    type: "text",
                    text: entry.name,
                  }
                end,
              }
            when "constant_details"
              puts "[MCP] Received constant_details tool request"
              fully_qualified_name = params.dig(:arguments, :fully_qualified_name)
              *nestings, name = fully_qualified_name.delete_prefix("::").split("::")
              entries = @index.resolve(name, nestings) || []
              type = case entries.first
              when RubyIndexer::Entry::Class
                "class"
              when RubyIndexer::Entry::Module
                "module"
              else
                "unknown"
              end
              content = <<~TEXT
                name: #{name}
                nestings: #{nestings.join(", ")}
                type: #{type}
                documentation: #{markdown_from_index_entries(name, entries)}
              TEXT
              {
                content: [
                  {
                    type: "text",
                    text: content,
                  },
                ],
              }
            when "class_details"
              puts "[MCP] Received class_details tool request"
              class_name = params.dig(:arguments, :class_name)
              ancestors = @index.linearized_ancestors_of(class_name)
              methods = @index.method_completion_candidates(nil, class_name)

              content = <<~TEXT
                name: #{class_name}
                ancestors: #{ancestors.join(", ")}
                methods: #{methods.map(&:name).join(", ")}
              TEXT

              {
                content: [
                  {
                    type: "text",
                    text: content,
                  },
                ],
              }
            end
          }
        end
      end
    end

    sig { params(socket: Socket, status: Integer, body: String).void }
    def respond(socket, status, body)
      socket.write("HTTP/1.1 #{status}\r\n")
      socket.write("Content-Type: application/json\r\n")
      socket.write("Connection: close\r\n")
      socket.write("Content-Length: #{body.bytesize}\r\n")
      socket.write("\r\n")

      # Write data in chunks to avoid blocking indefinitely on large responses
      offset = 0
      chunk_size = 8192 # 8KB chunks

      while offset < body.bytesize
        # Check if socket is writable before attempting write
        _, writable, = IO.select(nil, [socket], nil, 1)
        break unless writable

        current_chunk = body.byteslice(offset, chunk_size)
        bytes_written = socket.write(current_chunk)
        offset += bytes_written

        # Break if we couldn't write anything (possible socket issue)
        break if bytes_written <= 0
      end

      # Check if socket is writable before flush
      _, writable, = IO.select(nil, [socket], nil, 1)
      socket.flush if writable
    rescue Errno::EPIPE => e
      puts "[MCP] Broken pipe while sending response: #{e.message}"
    rescue Errno::ECONNRESET => e
      puts "[MCP] Connection reset while sending response: #{e.message}"
    rescue => e
      puts "[MCP] Error sending response: #{e.class} - #{e.message}"
      puts e.backtrace&.join("\n")
    end

    sig { params(socket: Socket, content_length: Integer).returns(String) }
    def read_request_body(socket, content_length)
      body = +""
      remaining = content_length
      deadline = Time.now + 5 # 5 second timeout

      while remaining > 0
        # Check timeout
        if Time.now > deadline
          puts "[MCP] Timeout reading request body"
          break
        end

        # Use IO.select to check if socket is readable
        readable, = IO.select([socket], nil, nil, 0.5)
        unless readable
          next # Socket not ready, try again
        end

        begin
          chunk = socket.read_nonblock([remaining, 8192].min)
          if chunk.empty?
            puts "[MCP] Client closed connection during body read"
            break
          end
          body << chunk
          remaining -= chunk.bytesize
        rescue EOFError => e
          puts "[MCP] EOF while reading request body: #{e.message}"
          break
        rescue Errno::EPIPE => e
          puts "[MCP] Broken pipe while reading request body: #{e.message}"
          break
        rescue Errno::ECONNRESET => e
          puts "[MCP] Connection reset while reading request body: #{e.message}"
          break
        rescue IO::WaitReadable
          # Socket not ready, try again after select
          next
        rescue => e
          puts "[MCP] Error reading request body: #{e.class} - #{e.message}"
          puts e.backtrace&.join("\n")
          break
        end
      end

      body
    end

    #: (RubyIndexer::Entry) -> String
    def generate_entry_text(entry)
      case entry
      when RubyIndexer::Entry::Class, RubyIndexer::Entry::Module
        <<~TEXT
          type: #{entry.is_a?(RubyIndexer::Entry::Class) ? "class" : "module"}
          name: #{entry.name}
          comments: #{entry.comments}
          uri: #{entry.uri}
        TEXT
      else
        entry.name
      end
    end
  end
end
