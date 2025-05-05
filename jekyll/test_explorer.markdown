---
layout: default
title: Test explorer
parent: VS Code extension
---

# Test explorer

{: .important }
The new test explorer implementation is currently being rolled out to users! You can adopt it early by toggling this
feature flag in your user or workspace settings<br>
"rubyLsp.featureFlags": { "fullTestDiscovery": true }

The Ruby LSP implements VS Code's [test explorer](https://code.visualstudio.com/docs/debugtest/testing), which allows
users to execute the tests defined in their codebase in 4 modes directly from inside the editor:

- Run (default mode): runs the selected tests and displays results in the test results panel
- Run in terminal: runs the selected tests in a terminal set up by the Ruby LSP
- Debug: starts an interactive debugging session for the selected tests
- Coverage: runs tests in coverage mode and shows results inside the editor

![Test explorer demo](images/test_explorer.gif)

## Design

Our design is based on addressing 2 main goals:

1. Supporting Ruby's diverse test frameworks without the need for extra editor extensions
2. Ensuring the solution is performant enough for large scale applications

With these in mind, the Ruby LSP populates the test explorer panel through static analysis. Loading every single test
into memory to perform runtime introspection as a discovery mechanism would not satisfy our performance goal. Tests
are discovered for the entire codebase automatically when:

- the user clicks one of the test related [code lenses](index#code-lens)
- the user expands the explorer

Support for different frameworks can be provided via our [add-on API](add-ons), both for discovering tests and defining how to execute them. Any framework contribution made via add-ons is automatically integrated with all modes
of execution. By default, the Ruby LSP supports Minitest and Test Unit. When working on Rails applications, the Rails
add-on is automatically included to support the declarative syntax included by `ActiveSupport::TestCase`.

{: .important }
There is limited support to using multiple test frameworks in the same codebase. This use case is pretty uncommon
and we will not make further investments into supporting it, in line with our design principle of [favoring common
setups](design-and-roadmap#favoring-common-development-setups)

### Dynamically defined tests

There is limited support for tests defined via meta-programming. Initially, they will not be present in the test
explorer (as they often cannot be detected through static analysis). However, running a test file that includes
dynamically defined tests will automatically populate the explorer with those tests, including the results of the
execution.

```ruby
class MyTest < Minitest::Spec
  # These are detected automatically
  describe "something" do
    it "does a useful thing" do
    end
  end

  # Dynamically defined tests like these are only discovered while running the entire file
  [:first, :second, :third].each do |name|
    it "does the #{name} well" do
    end
  end
end
```

### Tests that accept external parameters

In Ruby, you can write tests that accept external parameters, like environment variables.

```ruby
class MyTest < Minitest::Test
  # Using instance variable as an external argument
  if ENV["INCLUDE_SLOW_TESTS"]
    def test_slow_operation
    end
  end

  # Using command line arguments to gate tests
  if ARGV.include?("--integration-tests")
    def test_integration
    end
  end

  def test_other_things
  end
end
```

Automatically detecting what type of external argument is required for each test is not trivial. Additionally, VS
Code's test explorer doesn't have support for arguments when running tests out of the box and neither do its test
items accept metadata. This scenario will not be supported by the Ruby LSP.

## Customization

When tests are running through any execution mode, we set the `RUBY_LSP_TEST_RUNNER` environment variable to allow
users to customize behavior of their test suite if needed.

{: .important }
The Ruby LSP uses a custom test reporter to be able to communicate between extension and server. Some gems that modify
reporters may break this integration. The `RUBY_LSP_TEST_RUNNER` variable can be used to turn off these gems only when
running under the Ruby LSP's integrations.

{: .important }
Using coverage mode **does not require any extra dependencies or configuration** for collecting the coverage data. This is done automatically by the Ruby LSP through Ruby's built-in coverage API.

For example

```ruby
# test/test_helper.rb

unless ENV["RUBY_LSP_TEST_RUNNER"]
  # Minitest reporters cannot be used when running through the Ruby LSP integrations as it breaks our custom reporter

  require "minitest/reporters"
  Minitest::Reporters.use!(...)
end
```

Users can also differentiate between the mode of execution, which is the value of the `RUBY_LSP_TEST_RUNNER` variable:

```ruby
# test/test_helper.rb

case ENV["RUBY_LSP_TEST_RUNNER"]
when "run"
  # Do something when using run or run in terminal modes
when "debug"
  # Do something when using debug mode
when "coverage"
  # Do something when using coverage mode
else
  # Do something when running outside of the context of the Ruby LSP integration
end
```

## Other editors

The test explorer functionality is not yet standardized as part of the
[language server specification](https://microsoft.github.io/language-server-protocol/specification), which means that
it cannot be used by other editors without custom extension code to integrate all of the pieces together.

As most of the implementation is on server side, if any editor supports similar UI elements and editor-side APIs
(either directly or through plugins), it can integrate this feature as well. Below are the custom request
specifications.

### Discover tests

This request is sent by the client to discover which test items exist for a given text document URI.

Server capability: `capabilities.experimental.full_test_discovery`

Method: `rubyLsp/discoverTests`

Params:

```typescript
interface DiscoverTestParams {
  textDocument: {
    uri: string;
  };
}
```

Response:

```typescript
// Matches vscode.TestItem with some minor modifications
interface TestItem {
  id: string;
  label: string;
  uri: string;
  range: { start: { line: number; character: number }, end: { line: number; character: number }};
  tags: string[];
  children: TestItem[];
}

type Response = TestItem[];
```

### Resolve test commands

This request is sent by the client for the server to determine the minimum number of commands required to execute a
given hierarchy of tests. For example, if we execute a test group (class) inside of the bar_test.rb file and 3
examples inside of the `foo_test.rb` file, the minimum required commands to execute them may look like this:

```ruby
[
  "bin/rails test test/foo_test.rb:13:25:40",
  "bin/rails test test/bar_test.rb --name \"/^BarTest::NestedTest(#|::)/\""
]
```

Server capability: `capabilities.experimental.full_test_discovery`

Method: `rubyLsp/resolveTestCommands`

Params:

```typescript
type Params = TestItem[];
```

Response:

```typescript
interface ResolveTestCommandsResult {
  // The array of commands required to execute the tests
  commands: string[];

  // An optional array of custom LSP test reporters. Used to stream test results to the client side using JSON RPC
  // messages
  reporterPaths?: string[];
}
```
