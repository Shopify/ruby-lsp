---
layout: default
title: Test framework add-ons
nav_order: 10
parent: Add-ons
---

# Test framework add-ons

{: .note }
Before diving into building test framework add-ons, read about the [test explorer documentation](test_explorer) first.

The Ruby LSP's test explorer includes built-in support for Minitest and Test Unit. Add-ons can add support for other
test frameworks, like [Active Support test case](rails-add-on) and [RSpec](https://github.com/st0012/ruby-lsp-rspec).

There are 3 main parts for contributing support for a new framework:

- [Test discovery](#test-discovery): identifying tests within the codebase and their structure
- [Command resolution](#command-resolution): determining how to execute a specific test or group of tests
- Custom reporting: displaying test execution results in the test explorer

## Test discovery

Test discovery is the process of populating the explorer view with the tests that exist in the codebase. The Ruby LSP
extension is responsible for discovering all test files. The convention to be considered a test file is that it must
match this glob pattern: `**/{test,spec,features}/**/{*_test.rb,test_*.rb,*_spec.rb,*.feature}`. It is possible to
configure test frameworks to use different naming patterns, but this convention is established to guarantee that we
can discover all test files with adequate performance and without requiring configuration from users.

The part that add-ons are responsible for is discovering which tests exist **inside** of those files, which requires
static analysis and rules that are framework dependent. Like most other add-on contribution points, test discovery
can be enhanced by attaching a new listener to the process of discovering tests.

```ruby
module RubyLsp
  module MyTestFrameworkGem
    class Addon < ::RubyLsp::Addon
      #: (GlobalState, Thread::Queue) -> void
      def activate(global_state, message_queue)
        @global_state = global_state
      end

      # Declare the factory method that will hook a new listener into the test discovery process
      # @override
      #: (ResponseBuilders::TestCollection, Prism::Dispatcher, URI::Generic) -> void
      def create_discover_tests_listener(response_builder, dispatcher, uri)
        # Because the Ruby LSP runs requests concurrently, there are no guarantees that we'll be done executing
        # activate when a request for test discovery comes in. If this happens, skip until the global state is ready
        return unless @global_state

        # Create our new test discovery listener, which will hook into the dispatcher
        TestDiscoveryListener.new(response_builder, @global_state, dispatcher, uri)
      end
    end
  end
end
```

Next, the listener itself needs to be implemented. If the test framework being handled uses classes to define test
groups, like Minitest and Test Unit, the Ruby LSP provides a parent class to make some aspects of the implementation
easier and more standardized. Let's take a look at this case first and then see how frameworks that don't use classes
can be handled (such as RSpec).

In this example, test groups are defined with classes that inherit from `MyTestFramework::Test` and test examples are
defined by creating methods prefixed with `test_`.

```ruby
module RubyLsp
  module MyTestFrameworkGem
    class TestDiscoveryListener < Listeners::TestDiscovery
      #: (ResponseBuilders::TestCollection, GlobalState, Prism::Dispatcher, URI::Generic) -> void
      def initialize(response_builder, global_state, dispatcher, uri)
        super(response_builder, global_state, dispatcher, uri)

        # Register on the dispatcher for the node events we are interested in
        dispatcher.register(self, :on_class_node_enter, :on_def_node_enter)
      end

      #: (Prism::ClassNode node) -> void
      def on_class_node_enter(node)
        # Here we use the `with_test_ancestor_tracking` so that we can check if the class we just found inherits
        # from our framework's parent test class. This check is important because users can define any classes or
        # modules inside a test file and not all of them are runnable tests
        with_test_ancestor_tracking(node) do |name, ancestors|
          if ancestors.include?("MyTestFrameworkGem::Test")
            # If the test class indeed inherits from our framework, then we can create a new test item representing
            # this test in the explorer. The expected arguments are:
            #
            # - id: a unique ID for this test item. Must match the same IDs reported during test execution
            # (explained in the next section)
            # - label: the label that will appear in the explorer
            # - uri: the URI where this test can be found (e.g.: file:///Users/me/src/my_project/test/my_test.rb).
            # has to be a URI::Generic object
            # - range: a RubyLsp::Interface::Range object describing the range inside of `uri` where we can find the
            # test definition
            # - framework: a framework ID that will be used for resolving test commands. Each add-on should only
            # resolve the items marked as their framework
            test_item = Requests::Support::TestItem.new(
              name,
              name,
              @uri,
              range_from_node(node),
              framework: :my_framework
            )

            # Push the test item as an explorer entry
            @response_builder.add(test_item)

            # Push the test item for code lenses. This allows users to run tests by clicking the `Run`,
            # `Run in terminal` and `Debug` buttons directly on top of tests
            @response_builder.add_code_lens(test_item)
          end
        end
      end

      #: (Prism::DefNode) -> void
      def on_def_node_enter(node)
        # If the method is not public, then it cannot be considered an example. The visibility stack is tracked
        # automatically by the `RubyLsp::Listeners::TestDiscovery` parent class
        return if @visibility_stack.last != :public

        # If the method name doesn't begin with `test_`, then it's not a test example
        name = node.name.to_s
        return unless name.start_with?("test_")

        # The current group of a test example depends on which exact namespace nesting it is defined in. We can use
        # the Ruby LSP's index to get the fully qualified name of the current namespace using the `@nesting` variable
        # provided by the TestDiscovery parent class
        current_group_name = RubyIndexer::Index.actual_nesting(@nesting, nil).join("::")

        # The test explorer is populated with a hierarchy of items. Groups have children, which can include other
        # groups and examples. Listeners should always add newly discovered children to the parent item where they
        # are discovered. For example:
        #
        # class MyTest < MyFrameworkGem::Test
        #
        #   # this NestedTest is a child of MyTest
        #   class NestedTest < MyFrameworkGem::Test
        #
        #     # this example is a child of NestedTest
        #     def test_something; end
        #   end
        #
        #   # This example is a child of MyTest
        #   def test_something_else; end
        # end
        #
        # Get the current test item from the response builder using the ID. In this case, the immediate group
        # enclosing will be based on the nesting
        test_item = @response_builder[current_group_name]
        return unless test_item

        # Create the test item for the example. To make IDs unique, always include the group names as part of the ID
        # since users can define the same exact example name in multiple different groups
        example_item = Requests::Support::TestItem.new(
          "#{current_group_name}##{name}",
          name,
          @uri,
          range_from_node(node),
          framework: :my_framework,
        )

        # Add the example item to both as an explorer entry and code lens
        test_item.add(example_item)
        @response_builder.add_code_lens(example_item)
      end
    end
  end
end
```

{: .important }
Test item IDs have an implicit formatting requirement: groups must be separated by `::` and examples must be separated
by `#`. This is required even for frameworks that do not use classes and methods to define groups and examples.
Including spaces in group or example IDs is allowed.

For example, if we have the following test:

```ruby
class MyTest < MyFrameworkGem::Test
  class NestedTest < MyFrameworkGem::Test
    def test_something; end
  end
end
```

the expected ID for the item representing `test_something` should be `MyTest::NestedTest#test_something`.

For frameworks that do not define test groups using classes, such as RSpec, the listener should not inherit from
`RubyLsp::Listeners::TestDiscovery`. Instead, the logic can be implemented directly, based on the framework's specific
rules.

```ruby
module RubyLsp
  module MyTestFrameworkGem
    class MySpecListener
      #: (ResponseBuilders::TestCollection, GlobalState, Prism::Dispatcher, URI::Generic) -> void
      def initialize(response_builder, global_state, dispatcher, uri)
        # Register on the dispatcher for the node events we are interested in
        dispatcher.register(self, :on_call_node_enter)

        @spec_name_stack = []
      end

      #: (Prism::CallNode) -> void
      def on_call_node_enter(node)
        method_name = node.message

        case method_name
        when "describe", "context"
          # Extract the name of this group from the call node's arguments
          # Create a test item and push it as entries and code lenses
          # Push the name of this group into the stack, so that we can find which group is current later
        when "it"
          # Extract the name of this example from the call node's arguments
          # Create a test item and push it as entries and code lenses
        end
      end
    end
  end
end
```

## Command resolution

Command resolution is the process of receiving a hierarchy of tests selected in the UI and determining the shell commands required to run them. It's important that we minimize the number of these commands, to avoid having to spawn too many Ruby processes.

For example, this is what consolidated commands could look like when trying to run two specific examples in different
frameworks:

```shell
# Rails style execution (very similar to RSpec)
bin/rails test /project/test/models/user_test.rb:10:25

# Test Unit style execution based on regexes
bundle exec ruby -Itest /test/model_test.rb --testcase \"/^ModelTest\\$/\" --name \"/test_something\\$/

# Minitest style execution based on regexes
bundle exec ruby -Itest /test/model_test.rb --name \"/^ModelTest#test_something\\$/\"
```

The add-on's responsibility is to figure out how to execute test items that are associated with the framework they add
support for. Add-ons mark test items with the right framework during discovery and should only resolve items that
belong to them.

Another important point is that test groups with an empty children array are being fully executed. For example:

```ruby
# A test item hierarchy that means: execute the ModelTest#test_something specific example and no other tests
[
  {
    id: "ModelTest",
    uri: "file:///test/model_test.rb",
    label: "ModelTest",
    range: {
      start: { line: 0, character: 0 },
      end: { line: 30, character: 3 },
    },
    tags: ["framework:minitest", "test_group"],
    children: [
      {
        id: "ModelTest#test_something",
        uri: "file:///test/model_test.rb",
        label: "test_something",
        range: {
          start: { line: 1, character: 2 },
          end: { line: 10, character: 3 },
        },
        tags: ["framework:minitest"],
        children: [],
      },
    ],
  },
]

# A test item hierarchy that means: execute the entire ModelTest group with all examples and nested groups inside
[
  {
    id: "ModelTest",
    uri: "file:///test/model_test.rb",
    label: "ModelTest",
    range: {
      start: { line: 0, character: 0 },
      end: { line: 30, character: 3 },
    },
    tags: ["framework:minitest", "test_group"],
    children: [],
  },
]
```

Add-ons can define the `resolve_test_commands` method to define how to resolve the commands required to execute a
hierarchy. It is the responsibility of the add-on to filter the hierarchy to only the items that are related to them.

```ruby
module RubyLsp
  module MyTestFrameworkGem
    class Addon < ::RubyLsp::Addon
      # Items is the hierarchy of test items to be executed. The return is the list of minimum shell commands required
      # to run them
      #: (Array[Hash[Symbol, untyped]]) -> Array[String]
      def resolve_test_commands(items)
        commands = []
        queue = items.dup

        until queue.empty?
          item = queue.shift
          tags = Set.new(item[:tags])
          next unless tags.include?("framework:my_framework")

          children = item[:children]

          if tags.include?("test_dir")
            # Handle running entire directories
          elsif tags.include?("test_file")
            # Handle running entire files
          elsif tags.include?("test_group")
            # Handle running groups
          else
            # Handle running examples
          end

          queue.concat(children) unless children.empty?
        end

        commands
      end
    end
  end
end
```

You can refer to implementation examples for [Minitest and Test Unit](https://github.com/Shopify/ruby-lsp/blob/d86f4d4c567a2a3f8ae6f69caa10e21c4066e23e/lib/ruby_lsp/listeners/test_style.rb#L10) or [Rails](https://github.com/Shopify/ruby-lsp-rails/blob/cb9556d454c8bb20a1a73a99c8deb8788a520007/lib/ruby_lsp/ruby_lsp_rails/rails_test_style.rb#L11).
