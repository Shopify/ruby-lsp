# typed: true
# frozen_string_literal: true

require "test_helper"

module RubyLsp
  class MCPServerTest < Minitest::Test
    def setup
      @global_state = GlobalState.new
      @server = MCPServer.new(@global_state)
      @index = @global_state.index
    end

    def teardown
      # Avoid printing closing message
      capture_io do
        @server.stop
      end
    end

    def test_handle_get_classes_and_modules_no_query
      # Index some sample classes and modules
      @index.index_single(URI("file:///fake.rb"), <<~RUBY)
        class Foo; end
        module Bar; end
      RUBY

      tool = RubyLsp::MCP::GetClassesAndModules.new(@index)
      result = tool.call({})
      expected_yaml = [{ name: "Foo", type: "class" }, { name: "Bar", type: "module" }].to_yaml
      expected_result = [{ type: "text", text: expected_yaml }]

      assert_equal(expected_result, result)
    end

    def test_handle_get_classes_and_modules_with_query
      # Index some sample classes and modules
      @index.index_single(URI("file:///fake.rb"), <<~RUBY)
        class FooClass; end
        module FooModule; end
        class AnotherClass; end
      RUBY

      tool = RubyLsp::MCP::GetClassesAndModules.new(@index)
      result = tool.call({ "query" => "Foo" })
      expected_yaml = [{ name: "FooClass", type: "class" }, { name: "FooModule", type: "module" }].to_yaml
      expected_result = [{ type: "text", text: expected_yaml }]

      assert_equal(expected_result, result)
    end

    def test_handle_get_classes_and_modules_too_many_results
      original_max_classes = RubyLsp::MCP::Tool::MAX_CLASSES_TO_RETURN
      RubyLsp::MCP::Tool.const_set(:MAX_CLASSES_TO_RETURN, 1)

      # Index more classes than the limit
      @index.index_single(URI("file:///fake.rb"), <<~RUBY)
        class Class1; end
        class Class2; end
      RUBY

      tool = RubyLsp::MCP::GetClassesAndModules.new(@index)
      result = tool.call({})

      assert_equal(2, result.size)
      assert_equal("text", result.dig(0, :type))
      assert_equal(
        "Too many classes and modules to return, please narrow down your request with a query.",
        result.dig(0, :text),
      )
      assert_equal("text", result.dig(1, :type))
      # Check that only the first MAX_CLASSES_TO_RETURN are included
      expected_yaml = [{ name: "Class1", type: "class" }].to_yaml
      assert_equal(expected_yaml, result.dig(1, :text))
    ensure
      RubyLsp::MCP::Tool.const_set(:MAX_CLASSES_TO_RETURN, original_max_classes)
    end

    def test_handle_get_methods_details_instance_method
      uri = URI("file:///fake_instance.rb")
      @index.index_single(uri, <<~RUBY)
        class MyClass
          # Method comment
          def my_method(param1)
          end
        end
      RUBY

      tool = RubyLsp::MCP::GetMethodsDetails.new(@index)
      result = tool.call({ "signatures" => ["MyClass#my_method"] })
      entry = @index.resolve_method("my_method", "MyClass").first

      # Parse actual result
      result_yaml = Psych.unsafe_load(result.dig(0, :text))

      # Define expected simple values
      expected_receiver = "MyClass"
      expected_method = "my_method"
      # Define expected complex part (entry_details) as a hash
      expected_details_hash = [
        {
          uri: entry.uri,
          visibility: entry.visibility,
          comments: entry.comments.is_a?(Array) ? entry.comments.join("\n") : entry.comments,
          parameters: entry.decorated_parameters,
          owner: "MyClass",
        },
      ]

      # Compare simple fields
      assert_equal(expected_receiver, result_yaml[:receiver])
      assert_equal(expected_method, result_yaml[:method])
      # Compare the entry_details part by converting both back to YAML strings
      assert_equal(expected_details_hash.to_yaml, result_yaml[:entry_details].to_yaml)
    end

    def test_handle_get_methods_details_singleton_method
      uri = URI("file:///fake_singleton.rb")
      @index.index_single(uri, <<~RUBY)
        class MyClass
          # Singleton method comment
          def self.my_singleton_method
          end
        end
      RUBY

      singleton_class_name = "MyClass::<Class:MyClass>"
      tool = RubyLsp::MCP::GetMethodsDetails.new(@index)
      result = tool.call({ "signatures" => ["MyClass.my_singleton_method"] })
      entry = @index.resolve_method("my_singleton_method", singleton_class_name).first

      # Parse actual result
      result_yaml = Psych.unsafe_load(result.dig(0, :text))

      # Define expected simple values
      expected_receiver = "MyClass"
      expected_method = "my_singleton_method"
      # Define expected complex part (entry_details) as a hash
      expected_details_hash = [
        {
          uri: entry.uri,
          visibility: entry.visibility,
          comments: entry.comments.is_a?(Array) ? entry.comments.join("\n") : entry.comments,
          parameters: entry.decorated_parameters,
          owner: singleton_class_name,
        },
      ]

      # Compare simple fields
      assert_equal(expected_receiver, result_yaml[:receiver])
      assert_equal(expected_method, result_yaml[:method])
      # Compare the entry_details part by converting both back to YAML strings
      assert_equal(expected_details_hash.to_yaml, result_yaml[:entry_details].to_yaml)
    end

    def test_handle_get_methods_details_method_not_found
      @index.index_single(URI("file:///fake_not_found.rb"), "class MyClass; end")
      tool = RubyLsp::MCP::GetMethodsDetails.new(@index)
      result = tool.call({ "signatures" => ["MyClass#non_existent_method"] })
      assert_empty(result)
    end

    def test_handle_get_methods_details_receiver_not_found
      tool = RubyLsp::MCP::GetMethodsDetails.new(@index)
      result = tool.call({ "signatures" => ["NonExistentClass#method"] })
      assert_empty(result)
    end

    def test_handle_get_class_module_details_class
      uri = URI("file:///fake_class_details.rb")
      @index.index_single(uri, <<~RUBY)
        # Class Comment
        class MyDetailedClass
          def instance_method; end
          def self.singleton_method; end
        end
      RUBY

      tool = RubyLsp::MCP::GetClassModuleDetails.new(@index)
      result = tool.call({ "fully_qualified_names" => ["MyDetailedClass"] })
      entry = @index.resolve("MyDetailedClass", []).first

      expected_text = {
        name: "MyDetailedClass",
        nestings: [],
        type: "class",
        ancestors: ["MyDetailedClass"],
        methods: ["instance_method"],
        uris: [entry.uri],
        documentation: "__PLACEHOLDER__",
      }

      result_yaml = Psych.unsafe_load(result.dig(0, :text))
      actual_documentation = result_yaml.delete(:documentation)
      expected_text.delete(:documentation)

      assert_equal(1, result.size)
      assert_equal("text", result.dig(0, :type))
      # Compare the hash without documentation
      assert_equal(expected_text, result_yaml)
      # Assert documentation content separately
      assert_includes(actual_documentation, "Class Comment")
      assert_includes(actual_documentation, "**Definitions**: [fake_class_details.rb]")
    end

    def test_handle_get_class_module_details_module
      uri = URI("file:///fake_module_details.rb")
      @index.index_single(uri, <<~RUBY)
        # Module Comment
        module MyDetailedModule
          def instance_method_in_module; end
        end
      RUBY

      tool = RubyLsp::MCP::GetClassModuleDetails.new(@index)
      result = tool.call({ "fully_qualified_names" => ["MyDetailedModule"] })
      entry = @index.resolve("MyDetailedModule", []).first

      expected_text = {
        name: "MyDetailedModule",
        nestings: [],
        type: "module",
        ancestors: ["MyDetailedModule"],
        methods: ["instance_method_in_module"],
        uris: [entry.uri],
        documentation: "__PLACEHOLDER__",
      }

      result_yaml = Psych.unsafe_load(result.dig(0, :text))
      actual_documentation = result_yaml.delete(:documentation)
      expected_text.delete(:documentation)

      assert_equal(1, result.size)
      assert_equal("text", result.dig(0, :type))
      # Compare the hash without documentation
      assert_equal(expected_text, result_yaml)
      # Assert documentation content separately
      assert_includes(actual_documentation, "Module Comment")
      assert_includes(actual_documentation, "**Definitions**: [fake_module_details.rb]")
    end

    def test_handle_get_class_module_details_nested
      uri = URI("file:///fake_nested_details.rb")
      @index.index_single(uri, <<~RUBY)
        module Outer
          # Nested Class Comment
          class InnerClass
            def inner_method; end
          end
        end
      RUBY

      tool = RubyLsp::MCP::GetClassModuleDetails.new(@index)
      result = tool.call({ "fully_qualified_names" => ["Outer::InnerClass"] })
      entry = @index.resolve("InnerClass", ["Outer"]).first

      expected_text = {
        name: "Outer::InnerClass",
        nestings: ["Outer"],
        type: "class",
        ancestors: ["Outer::InnerClass"],
        methods: ["inner_method"],
        uris: [entry.uri],
        documentation: "__PLACEHOLDER__",
      }

      result_yaml = Psych.unsafe_load(result.dig(0, :text))
      actual_documentation = result_yaml.delete(:documentation)
      expected_text.delete(:documentation)

      assert_equal(1, result.size)
      assert_equal("text", result.dig(0, :type))
      # Compare the hash without documentation
      assert_equal(expected_text, result_yaml)
      # Assert documentation content separately
      assert_includes(actual_documentation, "Nested Class Comment")
      assert_includes(actual_documentation, "**Definitions**: [fake_nested_details.rb]")
    end

    def test_handle_get_class_module_details_not_found
      tool = RubyLsp::MCP::GetClassModuleDetails.new(@index)
      result = tool.call({ "fully_qualified_names" => ["NonExistentThing"] })

      expected_text = {
        name: "NonExistentThing",
        nestings: [],
        type: "unknown",
        ancestors: [],
        methods: [],
        uris: [],
        documentation: "__PLACEHOLDER__",
      }

      result_yaml = Psych.unsafe_load(result.dig(0, :text))
      actual_documentation = result_yaml.delete(:documentation)
      expected_text.delete(:documentation)

      assert_equal(1, result.size)
      assert_equal("text", result.dig(0, :type))
      # Compare the hash without documentation
      assert_equal(expected_text, result_yaml)
      # Assert documentation content separately (structure but no specific comment)
      assert_includes(actual_documentation, "**Definitions**: ")
      # Ensure no accidental comment appeared
      refute_match(/^[A-Za-z]/, actual_documentation.split("**Definitions**: ").last.strip)
    end
  end
end
