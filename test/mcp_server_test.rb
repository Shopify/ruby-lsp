# typed: true
# frozen_string_literal: true

require "test_helper"
require "socket"

module RubyLsp
  class MCPServerTest < Minitest::Test
    def setup
      @global_state = GlobalState.new
      @index = @global_state.index

      # Initialize the index with Ruby core - this is essential for method resolution!
      RubyIndexer::RBSIndexer.new(@index).index_ruby_core
      @mcp_server = MCPServer.new(@global_state)
      capture_io do
        @mcp_server.start
      end

      @mcp_port = @mcp_server.instance_variable_get(:@port)

      sleep(0.1)
    end

    def teardown
      capture_io do
        @mcp_server.stop
      end
    end

    def test_mcp_server_initialization
      response = send_mcp_request("initialize", {})

      assert_equal("2024-11-05", response.dig("protocolVersion"))
      assert_equal("ruby-lsp-mcp-server", response.dig("serverInfo", "name"))
      assert_equal("0.1.0", response.dig("serverInfo", "version"))
      assert(response.dig("capabilities", "tools"))
    end

    def test_tools_list
      response = send_mcp_request("tools/list", {})
      tools = response["tools"]

      assert_instance_of(Array, tools)
      tool_names = tools.map { |tool| tool["name"] }

      assert_includes(tool_names, "get_classes_and_modules")
      assert_includes(tool_names, "get_methods_details")
      assert_includes(tool_names, "get_class_module_details")
    end

    def test_get_classes_and_modules_no_query
      @index.index_single(URI("file:///fake.rb"), <<~RUBY)
        class Foo; end
        module Bar; end
      RUBY

      response = send_mcp_request("tools/call", {
        name: "get_classes_and_modules",
        arguments: {},
      })

      assert(response["content"])
      content_text = response.dig("content", 0, "text")

      # The format is: "{name: Foo, type: class}, {name: Bar, type: module}"
      # Extract class/module names using regex
      class_names = content_text.scan(/\{name: (\w+), type: (?:class|module)\}/).flatten

      # Now we get Ruby core classes too, so just verify our classes are included
      assert_includes(class_names, "Foo")
      assert_includes(class_names, "Bar")
    end

    def test_get_classes_and_modules_with_query
      @index.index_single(URI("file:///fake.rb"), <<~RUBY)
        class FooClass; end
        module FooModule; end
        class AnotherClass; end
      RUBY

      response = send_mcp_request("tools/call", {
        name: "get_classes_and_modules",
        arguments: { "query" => "Foo" },
      })

      content_text = response.dig("content", 0, "text")

      # Extract class/module names using regex
      class_names = content_text.scan(/\{name: (\w+), type: (?:class|module)\}/).flatten

      assert_includes(class_names, "FooClass")
      assert_includes(class_names, "FooModule")
    end

    def test_get_methods_details_instance_method
      uri = URI("file:///fake_instance.rb")
      @index.index_single(uri, <<~RUBY)
        class MyClass
          # Method comment
          def my_method(param1)
          end
        end
      RUBY

      response = send_mcp_request("tools/call", {
        name: "get_methods_details",
        arguments: { "signatures" => ["MyClass#my_method"] },
      })

      content_text = response.dig("content", 0, "text")

      assert_match(/receiver: MyClass/, content_text)
      assert_match(/method: my_method/, content_text)
      assert_match(/entry_details: \[/, content_text)
    end

    def test_get_methods_details_singleton_method
      uri = URI("file:///fake_singleton.rb")
      @index.index_single(uri, <<~RUBY)
        class MyClass
          # Singleton method comment
          def self.my_singleton_method
          end
        end
      RUBY

      response = send_mcp_request("tools/call", {
        name: "get_methods_details",
        arguments: { "signatures" => ["MyClass.my_singleton_method"] },
      })

      content_text = response.dig("content", 0, "text")

      assert_match(/receiver: MyClass/, content_text)
      assert_match(/method: my_singleton_method/, content_text)
      assert_match(/entry_details: \[/, content_text)
    end

    def test_get_methods_details_method_not_found
      @index.index_single(URI("file:///fake_not_found.rb"), "class MyClass; end")

      response = send_mcp_request("tools/call", {
        name: "get_methods_details",
        arguments: { "signatures" => ["MyClass#non_existent_method"] },
      })

      assert_equal("No results found", response.dig("content", 0, "text"))
    end

    def test_get_class_module_details_class
      uri = URI("file:///fake_class_details.rb")
      @index.index_single(uri, <<~RUBY)
        class MyDetailedClass
          def instance_method; end
          def self.singleton_method; end
        end
      RUBY

      response = send_mcp_request("tools/call", {
        name: "get_class_module_details",
        arguments: { "fully_qualified_names" => ["MyDetailedClass"] },
      })

      content_text = response.dig("content", 0, "text")

      assert_match(/name: "MyDetailedClass"/, content_text)
      assert_match(/type: "class"/, content_text)
      assert_match(/nestings: \[\]/, content_text)
      assert_match(/methods: \[.*"instance_method".*\]/, content_text)
    end

    def test_get_class_module_details_module
      uri = URI("file:///fake_module_details.rb")
      @index.index_single(uri, <<~RUBY)
        # Module Comment
        module MyDetailedModule
          def instance_method_in_module; end
        end
      RUBY

      response = send_mcp_request("tools/call", {
        name: "get_class_module_details",
        arguments: { "fully_qualified_names" => ["MyDetailedModule"] },
      })

      content_text = response.dig("content", 0, "text")

      assert_match(/name: "MyDetailedModule"/, content_text)
      assert_match(/type: "module"/, content_text)
      assert_match(/methods: \[.*"instance_method_in_module".*\]/, content_text)
    end

    def test_get_class_module_details_not_found
      response = send_mcp_request("tools/call", {
        name: "get_class_module_details",
        arguments: { "fully_qualified_names" => ["NonExistentThing"] },
      })

      content_text = response.dig("content", 0, "text")

      assert_match(/name: "NonExistentThing"/, content_text)
      assert_match(/type: "unknown"/, content_text)
      assert_match(/ancestors: \[\]/, content_text)
      assert_match(/methods: \[\]/, content_text)
    end

    def test_invalid_tool_name
      response = send_mcp_request("tools/call", {
        name: "non_existent_tool",
        arguments: {},
      })

      assert_equal("No results found", response.dig("content", 0, "text"))
    end

    def test_server_handles_malformed_json
      socket = TCPSocket.new("127.0.0.1", @mcp_port)
      socket.puts("{ invalid json")
      response_line = socket.gets #: as !nil
      socket.close

      response_data = JSON.parse(response_line)
      assert_equal("2.0", response_data["jsonrpc"])
      assert(response_data["error"])
    end

    private

    def send_mcp_request(method, params)
      request_data = {
        jsonrpc: "2.0",
        id: 1,
        method: method,
        params: params,
      }.to_json

      socket = TCPSocket.new("127.0.0.1", @mcp_port)
      socket.puts(request_data)
      response_line = socket.gets
      socket.close

      if response_line
        response_data = JSON.parse(response_line)
        if response_data["error"]
          raise "MCP request failed: #{response_data["error"]}"
        end

        response_data["result"]
      else
        raise "No response received from TCP server"
      end
    end
  end
end
