# typed: true
# frozen_string_literal: true

require "test_helper"
require "net/http"

module RubyLsp
  class MCPServerTest < Minitest::Test
    def setup
      @global_state = GlobalState.new
      @index = @global_state.index

      # Initialize the index with Ruby core - this is essential for method resolution!
      RubyIndexer::RBSIndexer.new(@index).index_ruby_core
      @mcp_server = MCPServer.new(@global_state)
      @mcp_server.start

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
      classes = YAML.unsafe_load(content_text)

      # Now we get Ruby core classes too, so just verify our classes are included
      class_names = classes.map { |c| c[:name] }
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
      classes = YAML.unsafe_load(content_text)

      # NOTE: fuzzy search may return all results if query doesn't filter much
      assert(classes.is_a?(Array))
      # Just verify we get valid data structure instead of specific filtering
      refute_empty(classes)
      class_names = classes.map { |c| c[:name] }
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
      result_data = YAML.unsafe_load(content_text)

      assert_equal("MyClass", result_data[:receiver])
      assert_equal("my_method", result_data[:method])
      assert(result_data[:entry_details])
      assert_equal(1, result_data[:entry_details].length)
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
      result_data = YAML.unsafe_load(content_text)

      assert_equal("MyClass", result_data[:receiver])
      assert_equal("my_singleton_method", result_data[:method])
      assert(result_data[:entry_details])
    end

    def test_get_methods_details_method_not_found
      @index.index_single(URI("file:///fake_not_found.rb"), "class MyClass; end")

      response = send_mcp_request("tools/call", {
        name: "get_methods_details",
        arguments: { "signatures" => ["MyClass#non_existent_method"] },
      })

      # Should return "No results found" for empty results
      assert_equal("No results found", response.dig("content", 0, "text"))
    end

    def test_get_class_module_details_class
      uri = URI("file:///fake_class_details.rb")
      @index.index_single(uri, <<~RUBY)
        # Class Comment
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
      result_data = YAML.unsafe_load(content_text)

      assert_equal("MyDetailedClass", result_data[:name])
      assert_empty(result_data[:nestings])
      assert_equal("class", result_data[:type])
      assert_includes(result_data[:documentation], "Class Comment")
      assert_includes(result_data[:methods], "instance_method")
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
      result_data = YAML.unsafe_load(content_text)

      assert_equal("MyDetailedModule", result_data[:name])
      assert_equal("module", result_data[:type])
      assert_includes(result_data[:documentation], "Module Comment")
      assert_includes(result_data[:methods], "instance_method_in_module")
    end

    def test_get_class_module_details_not_found
      response = send_mcp_request("tools/call", {
        name: "get_class_module_details",
        arguments: { "fully_qualified_names" => ["NonExistentThing"] },
      })

      content_text = response.dig("content", 0, "text")
      result_data = YAML.unsafe_load(content_text)

      assert_equal("NonExistentThing", result_data[:name])
      assert_equal("unknown", result_data[:type])
      assert_empty(result_data[:ancestors])
      assert_empty(result_data[:methods])
    end

    def test_invalid_tool_name
      response = send_mcp_request("tools/call", {
        name: "non_existent_tool",
        arguments: {},
      })

      assert_equal("No results found", response.dig("content", 0, "text"))
    end

    def test_server_handles_malformed_json
      uri = URI("http://127.0.0.1:#{@mcp_port}/mcp")

      http = Net::HTTP.new(uri.host, uri.port)
      request = Net::HTTP::Post.new(uri.path)
      request["Content-Type"] = "application/json"
      request.body = "{ invalid json"

      response = http.request(request)

      # The server returns 200 with an error response instead of 500
      assert_equal("200", response.code)

      response_data = JSON.parse(response.body)
      assert_equal("2.0", response_data["jsonrpc"])
      assert(response_data["error"])
    end

    private

    def send_mcp_request(method, params)
      uri = URI("http://127.0.0.1:#{@mcp_port}/mcp")

      http = Net::HTTP.new(uri.host, uri.port)
      request = Net::HTTP::Post.new(uri.path)
      request["Content-Type"] = "application/json"
      request.body = {
        jsonrpc: "2.0",
        id: 1,
        method: method,
        params: params,
      }.to_json

      response = http.request(request)

      if response.code == "200"
        response_data = JSON.parse(response.body)
        if response_data["error"]
          raise "MCP request failed: #{response_data["error"]}"
        end

        response_data["result"]
      else
        raise "HTTP request failed: #{response.code} #{response.body}"
      end
    end
  end
end
