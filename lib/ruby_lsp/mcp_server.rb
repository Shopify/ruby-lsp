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

    MAX_CLASSES_TO_RETURN = 5000

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

    sig { params(global_state: GlobalState).void }
    def initialize(global_state)
      @workspace_path = T.let(global_state.workspace_path, String)
      @port = T.let(self.class.find_available_port, Integer)

      # Write port to file
      port_file = File.join(@workspace_path, ".ruby-lsp", "mcp-port")
      File.write(port_file, @port.to_s)

      # Create TCP server
      @server = T.let(TCPServer.new("127.0.0.1", @port), TCPServer)
      @running = T.let(false, T::Boolean)
      @global_state = T.let(global_state, GlobalState)
      @index = T.let(global_state.index, RubyIndexer::Index)
    end

    sig { void }
    def start
      @running = true
      puts "[MCP] Server started on TCP port #{@port}"

      while @running
        sleep(0.1)
        begin
          # Use IO.select to check if the socket is ready
          ready = begin
            IO.select([@server], nil, nil, 0)
          rescue
            nil
          end

          if ready
            client_socket = @server.accept_nonblock
            Thread.start(client_socket) do |socket, _|
              handle_connection(socket)
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
      puts e.backtrace&.join("\n")
    ensure
      socket.close
    end

    sig { params(socket: Socket, body: String).void }
    def handle_mcp_request(socket, body)
      puts "[MCP] Received request: #{body}"

      response = process_jsonrpc_request(body)

      if response.nil?
        respond(socket, 500, {
          jsonrpc: "2.0",
          id: nil,
          error: {
            code: JsonRpcHandler::ErrorCode::InternalError,
            message: "Internal error",
            data: "No response from the server",
          },
        }.to_json)
      else
        respond(socket, 200, response)
      end
      puts "[MCP] Sent response: #{response}"
    end

    sig { params(json: String).returns(T.nilable(String)) }
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
              tools: [
                {
                  name: "get_classes_and_modules",
                  description: <<~DESCRIPTION,
                    Show all the indexed classes and modules in the current project and its dependencies when no query is provided.
                    When a query is provided, it'll return a list of classes and modules that match the query.
                    Doesn't support pagination and will return all classes and modules.
                    Stops after #{MAX_CLASSES_TO_RETURN} classes and modules.
                  DESCRIPTION
                  inputSchema: {
                    type: "object",
                    properties: {
                      query: {
                        type: "string",
                        description: "A query to filter the classes and modules",
                      },
                    },
                  },
                },
                {
                  # This may be redundant to some clients if they can access terminal to cat the files
                  # but it's useful for some clients that don't have that capability
                  name: "read_ruby_files",
                  description: <<~DESCRIPTION,
                    Read the contents of the given Ruby files, including files from dependencies.
                  DESCRIPTION
                  inputSchema: {
                    type: "object",
                    properties: {
                      file_uris: {
                        type: "array",
                        items: { type: "string" },
                      },
                    },
                    required: ["file_uris"],
                  },
                },
                {
                  name: "get_methods_details",
                  description: <<~DESCRIPTION,
                    Show the details of the given methods.
                    Use the following format for the signatures:
                    - Class#method
                    - Module#method
                    - Class.singleton_method
                    - Module.singleton_method

                    Details include:
                    - Comments
                    - Definition location
                    - Visibility
                    - Parameters
                    - Owner
                  DESCRIPTION
                  inputSchema: {
                    type: "object",
                    properties: {
                      signatures: {
                        type: "array",
                        items: { type: "string" },
                      },
                    },
                    required: ["signatures"],
                  },
                },
                {
                  name: "get_class_module_details",
                  description: <<~DESCRIPTION,
                    Show the details of the given classes/modules that are available in the current project and
                    its dependencies.
                    - Comments
                    - Definition location
                    - Methods
                    - Ancestors

                    Use `get_methods_details` tool to get the details of specific methods of a class/module.
                  DESCRIPTION
                  inputSchema: {
                    type: "object",
                    properties: {
                      fully_qualified_names: {
                        type: "array",
                        items: { type: "string" },
                      },
                    },
                    required: ["fully_qualified_names"],
                  },
                },
              ],
            }
          end
        when "tools/call"
          ->(params) {
            puts "[MCP] Received tools/call request: #{params.inspect}"
            contents = case params[:name]
            when "get_classes_and_modules"
              handle_get_classes_and_modules(params.dig(:arguments, :query))
            when "read_ruby_files"
              handle_read_ruby_files(params.dig(:arguments, :file_uris))
            when "get_methods_details"
              handle_get_methods_details(params.dig(:arguments, :signatures))
            when "get_class_module_details"
              handle_get_class_module_details(params.dig(:arguments, :fully_qualified_names))
            end

            generate_response(contents) if contents
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
      writable = T.let(nil, T.nilable(T::Array[IO])) # Initialize writable outside the loop

      while offset < body.bytesize
        # Check if socket is writable before attempting write
        _readable, writable, = IO.select(nil, [socket], nil, 1)
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
    rescue => e
      case e
      when Errno::EPIPE
        puts "[MCP] Broken pipe while sending response: #{e.message}"
        puts "[MCP] Response: #{body}"
      when Errno::ECONNRESET
        puts "[MCP] Connection reset while sending response: #{e.message}"
      end

      raise
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

    sig { params(contents: T::Array[T::Hash[Symbol, T.untyped]]).returns(T::Hash[Symbol, T.untyped]) }
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

    # Tool implementations
    sig { params(query: T.nilable(String)).returns(T::Array[T::Hash[Symbol, T.untyped]]) }
    def handle_get_classes_and_modules(query)
      class_names = @index.fuzzy_search(query).map do |entry|
        case entry
        when RubyIndexer::Entry::Class
          {
            name: entry.name,
            type: "class",
          }
        when RubyIndexer::Entry::Module
          {
            name: entry.name,
            type: "module",
          }
        end
      end.compact.uniq

      if class_names.size > MAX_CLASSES_TO_RETURN
        [
          {
            type: "text",
            text: "Too many classes and modules to return, please narrow down your request with a query.",
          },
          {
            type: "text",
            text: class_names.first(MAX_CLASSES_TO_RETURN).to_yaml,
          },
        ]
      else
        [
          {
            type: "text",
            text: class_names.to_yaml,
          },
        ]
      end
    end

    sig { params(file_uris: T::Array[String]).returns(T::Array[T::Hash[Symbol, T.untyped]]) }
    def handle_read_ruby_files(file_uris)
      file_uris.map do |file_uri|
        file_uri_obj = URI(file_uri)
        file_path = file_uri_obj.path
        next unless file_path

        begin
          file_content = File.read(file_path)
          {
            type: "text",
            text: {
              file_path: file_path,
              file_content: file_content,
            }.to_yaml,
          }
        rescue Errno::ENOENT
          {
            type: "text",
            text: {
              file_path: file_path,
              error: "File not found",
            }.to_yaml,
          }
        rescue => e
          {
            type: "text",
            text: {
              file_path: file_path,
              error: "Error reading file: #{e.message}",
            }.to_yaml,
          }
        end
      end.compact
    end

    sig { params(signatures: T::Array[String]).returns(T::Array[T::Hash[Symbol, T.untyped]]) }
    def handle_get_methods_details(signatures)
      signatures.map do |signature|
        entries = nil
        receiver = nil
        method = nil

        if signature.include?("#")
          receiver, method = signature.split("#")
          entries = @index.resolve_method(T.must(method), T.must(receiver))
        elsif signature.include?(".")
          receiver, method = signature.split(".")
          singleton_class = @index.existing_or_new_singleton_class(T.must(receiver))
          entries = @index.resolve_method(T.must(method), singleton_class.name)
        end

        next if entries.nil?

        entry_details = entries.map do |entry|
          {
            uri: entry.uri,
            visibility: entry.visibility,
            comments: entry.comments,
            parameters: entry.decorated_parameters,
            owner: entry.owner&.name,
          }
        end

        {
          type: "text",
          text: {
            receiver: receiver,
            method: method,
            entry_details: entry_details,
          }.to_yaml,
        }
      end.compact
    end

    sig { params(fully_qualified_names: T::Array[String]).returns(T::Array[T::Hash[Symbol, T.untyped]]) }
    def handle_get_class_module_details(fully_qualified_names)
      fully_qualified_names.map do |fully_qualified_name|
        *nestings, name = fully_qualified_name.delete_prefix("::").split("::")
        entries = @index.resolve(T.must(name), nestings) || []

        begin
          ancestors = @index.linearized_ancestors_of(fully_qualified_name)
          methods = @index.method_completion_candidates(nil, fully_qualified_name)
        rescue RubyIndexer::Index::NonExistingNamespaceError
          # If the namespace doesn't exist, we can't find ancestors or methods
          ancestors = []
          methods = []
        end

        type = case entries.first
        when RubyIndexer::Entry::Class
          "class"
        when RubyIndexer::Entry::Module
          "module"
        else
          "unknown"
        end

        {
          type: "text",
          text: {
            name: fully_qualified_name,
            nestings: nestings,
            type: type,
            ancestors: ancestors,
            methods: methods.map(&:name),
            uris: entries.map(&:uri),
            documentation: markdown_from_index_entries(T.must(name), entries),
          }.to_yaml,
        }
      end
    end
  end
end
