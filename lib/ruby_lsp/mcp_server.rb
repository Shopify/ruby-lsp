# typed: strict
# frozen_string_literal: true

require "socket"
require "json"
require "sorbet-runtime"

module RubyLsp
  class MCPServer
    extend T::Sig

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
          # Use IO.select with timeout to wait for connections instead of blocking accept
          ready = IO.select([@socket], nil, nil, 1) # 1 second timeout

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
              tools: {},
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
      when "tools/list"
        puts "[MCP] Received tools/list request"
        {
          jsonrpc: "2.0",
          id: request_id,
          result: {
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
                name: "fuzzy_search_entries",
                description: <<~DESCRIPTION,
                  Fuzzy search for class/module/method/constant entries in the current project and its dependencies
                  (gems).
                DESCRIPTION
                inputSchema: {
                  type: "object",
                  properties: {
                    query: {
                      type: "string",
                    },
                  },
                  required: ["query"],
                },
              },
              {
                name: "list_ancestors",
                description: "Show the ancestors of the given class",
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
          },
        }
      when "tools/call"
        puts "[MCP] Received tools/call request"
        params = request[:params]
        case params[:name]
        when "all_classes_entries"
          puts "[MCP] Received all_classes tool request"
          {
            jsonrpc: "2.0",
            id: request_id,
            result: {
              content: @index.instance_variable_get(:@entries).values.flatten.select do |entry|
                entry.is_a?(RubyIndexer::Entry::Class)
              end.map do |entry|
                {
                  type: "text",
                  text: entry.name,
                }
              end,
            },
          }
        when "fuzzy_search_entries"
          puts "[MCP] Received fuzzy_search_entries tool request"
          query = params.dig(:arguments, :query)
          entries = @index.prefix_search(query).flatten
          entries = @index.fuzzy_search(query) if entries.empty?
          {
            jsonrpc: "2.0",
            id: request_id,
            result: {
              content: entries.map do |entry|
                {
                  type: "text",
                  text: generate_entry_text(entry),
                }
              end,
            },
          }
        when "list_ancestors"
          puts "[MCP] Received list_ancestors tool request"
          class_name = params.dig(:arguments, :class_name)
          ancestors = @index.linearized_ancestors_of(class_name)
          content = ancestors.map do |ancestor|
            {
              type: "text",
              text: ancestor,
            }
          end
          {
            jsonrpc: "2.0",
            id: request_id,
            result: {
              content: content,
            },
          }
        else
          puts "[MCP] Unknown tool: #{params[:name]}"
          {
            jsonrpc: "2.0",
            id: request_id,
            error: {
              code: -32601,
              message: "Method not found",
              data: "Tool not supported: #{params[:name]}",
            },
          }
        end
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
