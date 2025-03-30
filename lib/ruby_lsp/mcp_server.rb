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

    MCP_FOLDER = "/tmp/ruby-mcp"
    MAX_CLASSES_TO_RETURN = 5000

    sig { params(global_state: GlobalState).void }
    def initialize(global_state)
      @socket_name = T.let(File.basename(global_state.workspace_path), String)
      unless Dir.exist?(MCP_FOLDER)
        Dir.mkdir(MCP_FOLDER)
      end
      @socket_path = T.let(File.join(MCP_FOLDER, @socket_name), String)
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
        sleep(0.1)
        begin
          # Use IO.select to check if the socket is ready
          ready = begin
            IO.select([@socket], nil, nil, 0)
          rescue
            nil
          end

          if ready
            client_socket = @socket.accept_nonblock
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
      @socket.close
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
                  name: "all_classes",
                  description: <<~DESCRIPTION,
                    Show all the indexed classes in the current project and its dependencies when no query is provided.
                    When a query is provided, it'll return a list of classes that match the query.
                    Doesn't support pagination and will return all classes.
                    Stops after #{MAX_CLASSES_TO_RETURN} classes.
                  DESCRIPTION
                  inputSchema: {
                    type: "object",
                    properties: {
                      query: {
                        type: "string",
                        description: "A query to filter the classes",
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
                  name: "methods_details",
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
                  name: "class_module_details",
                  description: <<~DESCRIPTION,
                    Show the details of the given classes/modules that are available in the current project and
                    its dependencies.
                    - Comments
                    - Definition location
                    - Methods
                    - Ancestors

                    Use `methods_details` tool to get the details of specific methods of a class/module.
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
            case params[:name]
            when "all_classes"
              query = params.dig(:arguments, :query)
              class_names = @index.fuzzy_search(query).map do |entry|
                entry.is_a?(RubyIndexer::Entry::Class) ? entry.name : nil
              end.compact.uniq

              contents =
                if class_names.size > MAX_CLASSES_TO_RETURN
                  [
                    {
                      type: "text",
                      text: "Too many classes to return, please narrow down your request with a query.",
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

              generate_response(contents)
            when "read_ruby_files"
              file_uris = params.dig(:arguments, :file_uris)
              file_contents = file_uris.map do |file_uri|
                file_uri = URI(file_uri)
                file_path = file_uri.path
                next unless file_path

                file_content = File.read(file_path)
                {
                  type: "text",
                  text: {
                    file_path: file_path,
                    file_content: file_content,
                  }.to_yaml,
                }
              end

              generate_response(file_contents)
            when "methods_details"
              signatures = params.dig(:arguments, :signatures)
              contents = signatures.map do |signature|
                entries = if signature.include?("#")
                  receiver, method = signature.split("#")
                  @index.resolve_method(method, receiver)
                elsif signature.include?(".")
                  receiver, method = signature.split(".")
                  singleton_class = @index.existing_or_new_singleton_class(receiver)
                  @index.resolve_method(method, singleton_class.name)
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

              generate_response(contents)
            when "class_module_details"
              fully_qualified_names = params.dig(:arguments, :fully_qualified_names)

              contents = fully_qualified_names.map do |fully_qualified_name|
                *nestings, name = fully_qualified_name.delete_prefix("::").split("::")
                ancestors = @index.linearized_ancestors_of(fully_qualified_name)
                methods = @index.method_completion_candidates(nil, fully_qualified_name)
                entries = @index.resolve(name, nestings) || []
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
                    documentation: markdown_from_index_entries(name, entries),
                  }.to_yaml,
                }
              end

              generate_response(contents)
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
  end
end
