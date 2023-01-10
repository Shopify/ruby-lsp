![Build Status](https://github.com/Shopify/ruby-lsp/workflows/CI/badge.svg)

# Ruby LSP

This gem is an implementation of the [language server protocol specification](https://microsoft.github.io/language-server-protocol/) for Ruby, used to improve editor features.

# Overview

The intention of Ruby LSP is to provide a fast, robust and feature-rich coding environment for Ruby developers.

It's part of a [wider Shopify goal](https://github.com/Shopify/vscode-shopify-ruby) to provide a state-of-the-art experience to Ruby developers using modern standards for cross-editor features, documentation and debugging.

It provides many features, including:

* Syntax highlighting
* Linting and formatting
* Code folding
* Selection ranges

It does not perform typechecking, so its features are implemented on a best-effort basis, aiming to be as accurate as possible.

Planned future features include:

* Auto-completion and navigation ("Go To Definition") ([prototype](https://github.com/Shopify/ruby-lsp/pull/429))
* Support for plug-ins to extend behavior

The Ruby LSP does not perform any type-checking or provide any type-related assistance, but it can be used alongside [Sorbet](https://github.com/sorbet/sorbet)'s LSP server.

At the time of writing, these are the major differences between Ruby LSP and [Solargraph](https://solargraph.org/):

* Solargraph [uses](https://solargraph.org/guides/yard) YARD documentation to gather information about your project and its gem dependencies. This provides functionality such as context-aware auto-completion and navigation ("Go To Definition")
* Solargraph can be used as a globally installed gem, but Ruby LSP must be added to the Gemfile or gemspec if using RuboCop. (There are pros and cons to each approach)

## Usage

Install the gem. There's no need to require it, since the server is used as a standalone executable.

```ruby
group :development do
  gem "ruby-lsp", require: false
end
```

If using VS Code, install the [Ruby LSP extension](https://github.com/Shopify/vscode-ruby-lsp) to get the extra features in
the editor.

See the [documentation](https://shopify.github.io/ruby-lsp) for more in-depth details about the
[supported features](https://shopify.github.io/ruby-lsp/RubyLsp/Requests.html).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/Shopify/ruby-lsp.
This project is intended to be a safe, welcoming space for collaboration, and contributors
are expected to adhere to the
[Contributor Covenant](https://github.com/Shopify/ruby-lsp/blob/main/CODE_OF_CONDUCT.md)
code of conduct.

### Running the test suite

Run the test suite with `bin/test`.

For more visibility into which tests are running, use the `SpecReporter`:

`SPEC_REPORTER=1 bin/test`

By default the tests run with warnings disabled to reduce noise. To enable warnings, pass `VERBOSE=1`.
Warnings are always shown when running in CI.

### Expectation testing

To simplify the way we run tests over different pieces of Ruby code, we use a custom expectations test framework against a set of Ruby fixtures.

We define expectations as `.exp` files, of which there are two variants:
* `.exp.rb`, to indicate the resulting code after an operation.
* `.exp.json`, consisting of a `result`, and an optional set of input `params`.

To add a new fixture to the expectations test suite:

1. Add a new fixture `my_fixture.rb` file under `test/fixtures`
2. (optional) Add new expectations under `test/expectations/$HANDLER` for the request handlers you're concerned by
3. Profit by running `bin/test test/requests/$HANDLER_expectations_test my_fixture`
    * Handlers for which you added expectations will be checked with `assert_expectations`
    * Handlers without expectations will be ran against your new test to check that nothing breaks

To add a new expectations test runner for a new request handler:

1. Add a new file under `test/requests/$HANDLER_expectations_test.rb` that subclasses `ExpectationsTestRunner` and calls `expectations_tests $HANDLER, "$EXPECTATIONS_DIR"` where: `$HANDLER` is the fully qualified name or your handler class and `$EXPECTATIONS_DIR` is the directory name where you want to store the expectation files.

   ```rb
   # frozen_string_literal: true

   require "test_helper"
   require "expectations/expectations_test_runner"

   class $HANDLERExpectationsTest < ExpectationsTestRunner
     expectations_tests RubyLsp::Requests::$HANDLER, "$EXPECTATIONS_DIR"
   end
   ```

2. (optional) Override the `run_expectations` and `assert_expectations` methods if needed. See the different request handler expectations runners under `test/requests/*_expectations_test.rb` for examples.

4. (optional) Add new fixtures for your handler under `test/fixtures`

5. (optional) Add new expectations under `test/expectations/$HANDLER`
   * No need to write the expectations by hand, just run the test with an empty expectation file and copy from the output.

7. Profit by running, `bin/test test/expectations_test $HANDLER`
    * Tests with expectations will be checked with `assert_expectations`
    * Tests without expectations will be ran against your new $HANDLER to check that nothing breaks

## Debugging

### Tracing LSP requests and responses

LSP server tracing can be controlled through the `ruby lsp.trace.server` config key in the `.vscode/settings.json` config file.

Possible values are:

* `off`: no tracing
* `messages`: display requests and responses notifications
* `verbose`: display each request and response as JSON

### Debugging using VS Code

The `launch.json` contains a 'Minitest - current file' configuration for the debugger.

1. Add a breakpoint using the VS Code UI.
1. Open the relevant test file.
1. Open the **Run and Debug** panel on the sidebar.
1. Ensure `Minitest - current file` is selected in the top dropdown.
1. Press `F5` OR click the green triangle next to the top dropdown. VS Code will then run the test file with debugger activated.
1. When the breakpoint is triggered, the process will pause and VS Code will connect to the debugger and activate the debugger UI.
1. Open the Debug Console view to use the debugger's REPL.

## License

The gem is available as open source under the terms of the
[MIT License](https://github.com/Shopify/ruby-lsp/blob/main/LICENSE.txt).
