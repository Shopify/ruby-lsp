# CONTRIBUTING

## Running the test suite

The test suite can be executed by running
```shell
# The default runner
bin/test
# or the spec reporter
SPEC_REPORTER=1 bin/test
# Warning are turned off by default. If you wish to see warnings use
VERBOSE=1 bin/test
```

## Expectation testing

To simplify the way we run tests over different pieces of Ruby code, we use a custom expectations test framework against
a set of Ruby fixtures.

All fixtures are defined under `test/fixtures`. By default, every request will be executed against every fixture
and the test framework will assert that nothing was raised to verify if all requests succeed in processing all fixtures.

Expectations can be added on a per request and per fixture basis. For example, we can have expectations for semantic
highlighting for a fixture called `foo.rb`, but no expectations for the same fixture for any other requests.

We define expectations as `.exp` files, of which there are two variants:
- `.exp.rb`, to indicate the resulting code after an operation
- `.exp.json`, consisting of a `result`, and an optional set of input `params`

To add a new test scenario

1. Add a new fixture `my_fixture.rb` file under `test/fixtures`
2. For applicable requests, add expectation files related to this fixutre. For example,
`test/expectations/semantic_highlighting/my_fixture.exp.json`

To add a new expectations test runner for a new request handler:

- Add a new file under `test/requests/MY_REQUEST_expectations_test.rb`

```ruby
# frozen_string_literal: true

require "test_helper"
require "expectations/expectations_test_runner"

class MyRequestExpectationsTest < ExpectationsTestRunner
  # The first argument is the fully qualified name of the request class
  # The second argument is the folder name where the expectation files are
  expectations_tests RubyLsp::Requests::MyRequest, "my_request"
end
```

- (optional) The default behaviour of running tests is not always enough for every request. You may need to override
the base run and assert method to achieve the right behaviour. See `diagnostics_expectations_test.rb` for an
example

```ruby
# frozen_string_literal: true

require "test_helper"
require "expectations/expectations_test_runner"

class MyRequestExpectationsTest < ExpectationsTestRunner
  expectations_tests RubyLsp::Requests::MyRequest, "my_request"

  def run_expectations(source)
    # Run your request for the given source
  end

  def assert_expectations(source, expected)
    # Invoke run_expectations and then customize how to assert the correct responses
  end
end
```

## Debugging with VS Code

## Debugging Tests

1. Open the test file
2. Set breakpoints in the code as desired
3. Click the debug button on top of test examples

## Debugging Running Ruby LSP Process

1. Open [vscode-ruby-lsp](https://github.com/Shopify/vscode-ruby-lsp) in VS Code
2. Under `Run and Debug`, select `Run extension` and click the start button (or press F5)
3. The extension host window opened will be running a Ruby LSP process with the debugger attached. To start debugging
the live process, go under `Run and Debug`, select `Attach to existing server` and click the start button (or
press F5)
4. Add breakpoints and perform the actions necessary for triggering the requests you wish to debug

## Spell Checking

VS Code users will be prompted to enable the [Code Spell
Checker](https://marketplace.visualstudio.com/items?itemName=streetsidesoftware.code-spell-checker) extension. By
default this will be enabled for all workspaces, but you can choose to selectively enable or disable it per workspace.

If you introduce a word which the spell checker does not recognize, you can add it to the `cspell.json` configuration
alongside your PR.
