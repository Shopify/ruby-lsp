![Build Status](https://github.com/Shopify/ruby-lsp/workflows/CI/badge.svg)

# Ruby LSP

This gem is an implementation of the [language server protocol specification](https://microsoft.github.io/language-server-protocol/) for Ruby, used to improve editor features.

## Usage

Install the gem. There's no need to require it, since the server is used as a standalone executable.

```ruby
group :development do
  gem "ruby-lsp", require: false
end
```

If using VS Code, install the [Ruby LSP plugin](https://github.com/Shopify/vscode-ruby-lsp) to get the extra features in
the editor.

See the [documentation](https://shopify.github.io/ruby-lsp) for
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

The `launch.json` contains two configurations for the debugger:

1. You can use the `Minitest - current file` to run tests with the debugger activated.

2. You can use `Attach with rdbg` to attach to the active ruby-lsp server process.

You may encounter an error dialog with a long message beginning `Command failed: /bin/zsh -l -c 'rdbg --util=list-socks'`.
The underlying cause is similar to https://github.com/ruby/vscode-rdbg/issues/21.
To work around it, you can remove the `rdbg` binstub, which causes the globally installed `rdbg` to be used instead:

```
rm `which rdbg`
```

### Debugging using the command line

You can attach to the ruby-lsp process from the command line with:

`bundle exec rdbg --attach`

## License

The gem is available as open source under the terms of the
[MIT License](https://github.com/Shopify/ruby-lsp/blob/main/LICENSE.txt).
