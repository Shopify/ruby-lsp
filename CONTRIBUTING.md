# CONTRIBUTING

This repository contains three sub-projects:

- the **language server** (`ruby-lsp`), which exists at the top level of the repository. Most features are implemented here since everything implemented in the server is available to all editors
- the **VS Code extension**, which exists under the `vscode` directory. Any custom VS Code features are implemented here
- the **documentation** website, which exists under the `jekyll` directory. All user facing documentation for both the Ruby LSP and the Rails add-on is contained here

This contributing guide is split by each component.

## Initial setup

To start contributing to the Ruby LSP, ensure that all dependencies are installed as follows:

- `bundle install` on the top level will install Ruby dependencies
- `bundle install` in the `jekyll` directory will install documentation dependencies
- `yarn install` in the `vscode` directory will install Node.js dependencies for the VS Code extension

## Contributing to the server

This is the structure of the `ruby-lsp` gem:

- `lib/ruby_indexer`: the code indexer to extract declarations from the workspace
- `lib/ruby_lsp/*.rb`: foundational pieces of the language server, such as workers, queues, handling requests and so on
- `lib/ruby_lsp/requests`: request implementation. These match one to one with the [language server specification](https://microsoft.github.io/language-server-protocol/specification)
- `lib/ruby_lsp/listeners`: Prism dispatcher listeners. Most of the server's infrastructure relies on a listener pattern to maximize performance while traversing ASTs. Note that a single request may depend on more than one listener

When adding or changing an existing feature, first identify which request is responsible for it in the
[specification](https://microsoft.github.io/language-server-protocol/specification). Then identify which file in the
server implements that request and start thinking about the implementation.

> [!NOTE]
>
> When using VS Code, open the `lsp.code-workspace` file instead of just opening the regular folder. It contains
> configurations for working with the sub projects side by side effectively

### Debugging

#### Live debugging the server

It is possible to live debug the development instance of the language server that is currently running when using VS
Code:

1. `CMD/CTRL + SHIFT + P` to open the command palette
2. Search for `Debug the Ruby LSP server`. This command will restart the server in debug mode, allowing you to connect
with a debugger. Note that the debug mode applies only until the editor is closed or Ruby LSP restarts
3. After the server has launched in debug mode, attach the debugger by going in `Run and debug`, selecting the `Attach to existing server` task and clicking run
4. You should now be able to put breakpoints in the UI and triggering requests will stop at those breakpoints

Caveat: since you are debugging the language server instance that is currently running in your own editor, features will
not be available if the execution is currently suspended at a breakpoint.

#### Understanding Prism ASTs

The Ruby LSP uses Prism to parse and understand Ruby code. When working on a feature, it's very common to need to
inspect the structure of the Prism AST for a given code snippet, so that you can understand why a request is being
triggered a certain way.

If you're using VS Code, you can use the [show syntax tree
command](https://shopify.github.io/ruby-lsp/#show-syntax-tree) to inspect the structure of an AST for an entire document
or selection.

For other editors, using our IRB configurations is the easiest way of achieving the same:

1. `bundle exec irb` to launch IRB with our configurations. It will require all libraries for you
2. Then parse the Ruby code you'd like to understand better and start inspecting

```ruby
source = <<~RUBY
  class Foo
    def bar
    end
  end
RUBY

ast = Prism.parse(source).value
```

Check the [Prism documentation](https://ruby.github.io/prism/) for more related information.

#### Tracing LSP requests and responses

In VS Code, you can verify what's happening in the server by enabling tracing, which allows for different levels of
logging.

```jsonc
{
  // Your JSON settings
  //
  // - `off`: no tracing
  // - `messages`: display requests and responses notifications
  // - `verbose`: display each request and response as JSON
  "ruby lsp.trace.server": "messages"
}
```

#### Manually testing a change

After you made a change or added a new feature, you can verify it in the editor by restarting the language server. In VS
Code, this can be achieved by running the command `Ruby LSP: restart`, which will reboot the server and pick up your
changes.

For other editors, you must manually restart the language server to pick up the latest changes.

#### Debugging tests

In VS Code, we recommend:

1. Setting breakpoints in the UI
2. Opening the test that will hit that breakpoint
3. Clicking the `debug` code lens button on top of examples

Alternatively (and for other editors), adding a `binding.b` statement in the code and executing the test in the terminal
will also allow you to debug the code.

### Writing tests

There are two types of tests in the Ruby LSP. The first type is likely familiar: standard Minitest files with a bunch of
examples inside using the method declaration syntax.

The second type of test is our fixture/expectation framework. Adding a new fixture under `test/fixtures` will
automatically make the framework run all requests against that fixture. By default, the framework only checks that the
features don't crash when running against the fixture. This is useful for ensuring that critical requests don't break
when using less common Ruby syntax.

To go beyond checking if the requests break for a fixture, you can add an expectation to `test/expectations/NAME_OF_THE_REQUEST`, which allows you to assert the expected response for a request and fixture combination.

For example, if we have a `test/fixtures/foo.rb`, then adding a `test/expectations/semantic_highlighting/foo.exp.json` will make the framework verify that when running semantic highlighting in the `foo.rb` fixture, the `foo.exp.json` response is expected.

Check existing fixture and expectation combinations for examples.

#### When to use each type of test

The fixture/expectation framework is intended to be used mostly by full document requests (language server features that
are computed for the entire file every time).

Requests and features that are position specific or that operate under a different mechanism should just use regular Minitest tests.

#### Running the test suite

There are multiple ways to execute tests available.

```shell
# Run the entire test suite
bundle exec rake

# Run only indexing tests
bundle exec rake test:indexer

# Run only language server tests (excluding indexing)
bundle exec rake test

# Using the custom test framework to run a specific fixture example
# bin/test test/requests/the_request_you_want_to_run_test.rb name_of_fixture
bin/test test/requests/diagnostics_expectations_test.rb def_bad_formatting
```

Additionally, we use RuboCop for linting and Sorbet for type checking.

```shell
# Run linting
bundle exec rubocop

# Run type checking
bundle exec srb tc
```

## Contributing to the VS Code extension

Before starting on this section, ensure that [dependencies are installed](#initial-setup).

In addition to what's described here, the [VS Code extension API documentation](https://code.visualstudio.com/api) is a
great place to gather more context about how extensions interact with the editor.

The VS Code extension currently has the following main parts:

- Version manager integrations for Ruby environment activation
- A [ruby/debug](https://github.com/ruby/debug) client implementation
- A [test controller](https://code.visualstudio.com/docs/editor/testing) implementation
- A [Copilot chat participant](https://code.visualstudio.com/api/extension-guides/chat)
- A dependencies tree implementation
- The LSP client
- A workspace abstraction to represent each active workspace in the editor

### Testing changes

We try to ensure thorough testing as much as possible. However, some tests are difficult to write, in particular those
that interact with VS Code widgets.

For example, if running the test displays a dialog, the test has no easy way of clicking a button on it to continue
execution. For these situations we use `sinon` to stub expected invocations and responses.

Note: `client.test.ts` is an integration style test that boots the development version of the `ruby-lsp` gem and runs
requests against it.

#### Running tests

The easiest way to run tests is by selecting the `Extension tests` task in `Run and debug` and clicking run. That will
run all tests and the results will appear in VS Code's debug console.

Alternatively, you can also run the tests through the terminal, which will download a test VS Code version inside the
repository and run tests against it. You can avoid the download by running the tests through the launch task.

Note: it is not possible to run a single test file or example.

### Live debugging

It is possible to live debug the development version of the extension. Detailed information can be found in the [VS Code
extension documentation]((https://code.visualstudio.com/api)), but this section includes a short description.

Live debugging involves two VS Code windows. The first one is where you will be modifying the code and the second window
will be where the development version of the extension is going to be running. You want to change the code in the first
window, reload and verify the changes in the second window.

1. Start by launching the extension debugging with the `Run extension` task in the `Run and debug` panel. This will open the second VS Code window where the development version of the extension is running
2. Make the desired changes in the first original VS Code window
3. Click the reload button in the [debug toolbar](https://code.visualstudio.com/Docs/editor/debugging#_user-interface) to load your recent changes into the second VS Code window
4. Perform the actions to verify your changes in the second window

If you wish to perform step by step debugging, all you have to do is add breakpoints through the UI in the first window
where you are modifying the code - not in the second window where the development version of the extension is running.

## Contributing to documentation

The Ruby LSP uses [Jekyll](https://jekyllrb.com/) to generate the documentation, whose source lives under the `/jekyll`
folder. Before making any changes, ensure you [performed initial setup](#initial-setup).

After that, follow these steps to make and verify your changes:

1. Make the desired changes
2. Launch jekyll in development
```shell
bundle exec jekyll serve
```

## Testing changes

### Tracing LSP requests and responses

LSP server tracing (logging) can be controlled through the `ruby lsp.trace.server` config key in the
`.vscode/settings.json` config file.

Possible values are:

- `off`: no tracing
- `messages`: display requests and responses notifications
- `verbose`: display each request and response as JSON

### Manually testing a change

There are a few options for manually testing changes to Ruby LSP:

You can test against Ruby LSP's own code if using VS Code, and you have the `ruby-lsp` project open. Choose 'Ruby LSP: Restart' from the command menu and the VS Code extension will detect that you are working on `ruby-lsp`, and use the locally checked out code instead of the installed extension.

The other way is to use a separate project, and add a Gemfile entry pointing to your local checkout of `ruby-lsp`, e.g.:

```
gem "ruby-lsp", path: "../../Shopify/ruby-lsp"
```

With both approaches, there is a risk of 'breaking' your local development experience, so keep an eye on the Ruby LSP output panel for exceptions as your make changes.

### Running the test suite

The test suite can be executed by running
```shell
# The default runner
bin/test
# or the spec reporter
SPEC_REPORTER=1 bin/test
# Warnings are turned off by default. If you wish to see warnings use
VERBOSE=1 bin/test
# Run a single test like this: "bin/test my_test.rb test_name_regex", e.g.
bin/test test/requests/diagnostics_expectations_test.rb test_diagnostics__def_bad_formatting
```

### Expectation testing

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
2. For applicable requests, add expectation files related to this fixture. For example,
`test/expectations/semantic_highlighting/my_fixture.exp.json`

To add a new expectations test runner for a new request handler:

- Add a new file under `test/requests/MY_REQUEST_expectations_test.rb`

```ruby
require "test_helper"
require_relative "support/expectations_test_runner"

class MyRequestExpectationsTest < ExpectationsTestRunner
  # The first argument is the fully qualified name of the request class
  # The second argument is the folder name where the expectation files are
  expectations_tests RubyLsp::Requests::MyRequest, "my_request"
end
```

- (optional) The default behavior of running tests is not always enough for every request. You may need to override
the base run and assert method to achieve the right behavior. See `diagnostics_expectations_test.rb` for an
example

```ruby
require "test_helper"
require_relative "support/expectations_test_runner"

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

To automatically create or update `.exp.json` files, you can use the `WRITE_EXPECTATIONS` environment variable. For example:

```sh
WRITE_EXPECTATIONS=1 bin/test test/requests/code_lens_expectations_test.rb
```

## Debugging with VS Code

## Debugging Tests

1. Open the test file
2. Set breakpoints in the code as desired
3. Click the debug button on top of test examples

## Live debugging

1. Under `Run and Debug`, select `Run extension` and click the start button (or press F5)
2. The extension host window opened will be running the development version of the VS Code extension. Putting break
points in the extension code will allow debugging
3. If you wish to debug the server process, go under `Run and Debug` in the extension host window,
select `Attach to existing server` and click the start button (or press F5)
3. Add breakpoints and perform the actions necessary for triggering the requests you wish to debug

## Screen Captures

We include animated screen captures to illustrate Ruby LSP features.
For recording new captures, use [LICEcap](https://www.cockos.com/licecap/).
For consistency, install the Ruby LSP profile included with this repo.
Configure LICEcap to record at 24fps, at 640 x 480.
If appropriate, you can adjust the height of the capture, but keep the width at 640.

## Spell Checking

VS Code users will be prompted to enable the [Code Spell
Checker](https://marketplace.visualstudio.com/items?itemName=streetsidesoftware.code-spell-checker) extension. By
default this will be enabled for all workspaces, but you can choose to selectively enable or disable it per workspace.

If you introduce a word which the spell checker does not recognize, you can add it to the `cspell.json` configuration
alongside your PR.
