![Build Status](https://github.com/Shopify/ruby-lsp/workflows/CI/badge.svg)

# Ruby LSP

This gem is an implementation of the language server protocol specification for Ruby, used to improve editor features.

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

### Expectation testing

To simplify the way we run tests over different pieces of Ruby code, we use a custom expectations test framework against a set of Ruby fixtures.

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

## License

The gem is available as open source under the terms of the
[MIT License](https://github.com/Shopify/ruby-lsp/blob/main/LICENSE.txt).
