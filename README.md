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

## How does ruby-lsp differ from Solargraph?

**Background**

In July 2021, Shopify quietly released [rubocop-lsp](https://github.com/Shopify/rubocop-lsp). In March 2022, that was succeeded by [ruby-lsp](https://github.com/Shopify/ruby-lsp).
As the name suggests, the newer library is intended to have a wider set of capabilities.
It has a corresponding [VS Code extension](https://github.com/Shopify/vscode-ruby-lsp).
ruby-lsp is widely used at Shopify, and is installed by default as part of most Ruby or Rails codebases.

Solargraph is an older project, first released in March 2017.
It was developed by [Castwide Technologies](https://castwide.com/), an Columbus, OH based company who provide various services including web hosting and software development.
It also has a corresponding [VS Code extension](https://marketplace.visualstudio.com/items?itemName=castwide.solargraph).

**Major Differences**

The biggest difference between the two libraries is their approach to understanding the structure of your code, and its dependencies.
This is used to provide capabilities such as intellisense (context-aware auto-completion) and navigation (e.g. Go To Definition).

Solargraph relies on [YARD](https://yardoc.org/), a popular tool for building documentation.
Developers run the `yard gems` command on their local machine to generate this information

ruby-lsp does not provide direct support for these features.
The intention is that they are handled by Sorbet’s LSP server, running alongside ruby-lsp.
This means some functionality is only available if the files are [typed at ‘true’ or higher](https://sorbet.org/docs/static#file-level-granularity-strictness-levels).
However there is some experimental work [in progress](https://github.com/Shopify/ruby-lsp/pull/429) to improve support for untyped code.

**Similarities**

Some LSP features are supported by both libraries, although it is likely there are differences in behaviour:

* Both libraries integrate with RuboCop for linting and auto-formatting. (Only ruby-lsp has a Quick Fix feature, allowing individual corrections.).
* Both support Code Folding

**Other differences**

Features only in ruby-lsp:

* Selection ranges (Expand Selection / Shrink Selection)
* Inlay hints
* Snippets

Features only in Solargraph:

* [Plugin support](https://solargraph.org/guides/plugins)

**Underlying Technologies**

To parse Ruby code, Solargraph uses https://github.com/whitequark/parser.
ruby-lsp uses https://github.com/ruby-syntax-tree/syntax_tree.

**Type Checking**

As mentioned previously, ruby-lsp relies on Sorbet for typechecking.

In Solargraph, type checking is described as a “work in progress” and is done “through a combination of YARD tag analysis and type inference”.

**Setup**

ruby-lsp requires that the gem be part of the Gemfile.

solargraph can be globally installed.

There are pros and cons to each approach.

## License

The gem is available as open source under the terms of the
[MIT License](https://github.com/Shopify/ruby-lsp/blob/main/LICENSE.txt).
