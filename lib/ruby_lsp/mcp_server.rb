# typed: strict
# frozen_string_literal: true

require "json"
require "webrick"
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

      # Create WEBrick server
      @server = T.let(
        WEBrick::HTTPServer.new(
          Port: @port,
          BindAddress: "127.0.0.1",
          Logger: WEBrick::Log.new(File.join(@workspace_path, ".ruby-lsp", "mcp-webrick.log")),
          AccessLog: [],
        ),
        WEBrick::HTTPServer,
      )

      # Mount the MCP handler
      @server.mount_proc("/mcp") do |req, res|
        handle_mcp_request(req, res)
      end

      @running = T.let(false, T::Boolean)
      @global_state = T.let(global_state, GlobalState)
      @index = T.let(global_state.index, RubyIndexer::Index)
    end

    sig { void }
    def start
      puts "[MCP] Server started on TCP port #{@port}"
      @server.start
    end

    sig { void }
    def stop
      puts "[MCP] Stopping server"
      @server.shutdown
    end

    private

    sig { params(request: WEBrick::HTTPRequest, response: WEBrick::HTTPResponse).void }
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
