[![Build Status](https://github.com/Shopify/ruby-lsp/workflows/CI/badge.svg)](https://github.com/Shopify/ruby-lsp/actions/workflows/ci.yml)
[![Ruby LSP extension](https://img.shields.io/badge/VS%20Code-Ruby%20LSP-success?logo=visual-studio-code)](https://marketplace.visualstudio.com/items?itemName=Shopify.ruby-lsp)
[![Ruby DX Slack](https://img.shields.io/badge/Slack-Ruby%20DX-success?logo=slack)](https://join.slack.com/t/ruby-dx/shared_invite/zt-1s6f4y15t-v9jedZ9YUPQLM91TEJ4Gew)


# Ruby LSP

The Ruby LSP is an implementation of the [language server protocol](https://microsoft.github.io/language-server-protocol/)
for Ruby, used to improve rich features in editors. It is a part of a wider goal to provide a state-of-the-art
experience to Ruby developers using modern standards for cross-editor features, documentation and debugging.

Want to discuss Ruby developer experience? Consider joining the public
[Ruby DX Slack workspace](https://join.slack.com/t/ruby-dx/shared_invite/zt-1s6f4y15t-v9jedZ9YUPQLM91TEJ4Gew).

## Usage

### With VS Code

If using VS Code, all you have to do is install the [Ruby LSP extension](https://github.com/Shopify/vscode-ruby-lsp) to
get the extra features in the editor. Do not install this gem manually.

### With other editors

See [editors](https://github.com/Shopify/ruby-lsp/blob/main/EDITORS.md) for community instructions on setting up the
Ruby LSP.

The gem can be installed by doing
```shell
gem install ruby-lsp
```

If you decide to add the gem to the bundle, it is not necessary to require it.
```ruby
group :development do
  gem "ruby-lsp", require: false
end
```

### Documentation

See the [documentation](https://shopify.github.io/ruby-lsp) for more in-depth details about the
[supported features](https://shopify.github.io/ruby-lsp/RubyLsp/Requests.html).

## Learn More

* [RubyConf 2022: Improving the development experience with language servers](https://www.youtube.com/watch?v=kEfXPTm1aCI) ([Vinicius Stock](https://github.com/vinistock))
* [Remote Ruby: Ruby Language Server with Vinicius Stock](https://remoteruby.com/221)

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

### Debugging

### Debugging Tests

1. Open the test file.
2. Set a breakpoint(s) on lines by clicking next to their numbers.
3. Open VS Code's `Run and Debug` panel.
4. At the top of the panel, select `Minitset - current file` and click the green triangle (or press F5).

### Debugging Running Ruby LSP Process

1. Open the `vscode-ruby-lsp` project in VS Code.
2. [`vscode-ruby-lsp`] Open VS Code's `Run and Debug` panel.
3. [`vscode-ruby-lsp`] Select `Run Extension` and click the green triangle (or press F5).
4. [`vscode-ruby-lsp`] Now VS Code will:
    - Open another workspace as the `Extension Development Host`.
    - Run `vscode-ruby-lsp` extension in debug mode, which will start a new `ruby-lsp` process with the `--debug` flag. Note that debugging is not available on Windows.
5. Open `ruby-lsp` in VS Code.
6. [`ruby-lsp`] Run `bin/rdbg -A` to connect to the running `ruby-lsp` process.
7. [`ruby-lsp`] Use commands like `b <file>:<line>` or `b Class#method` to set breakpoints and type `c` to continue the process.
8. In your `Extension Development Host` project (e.g. [`Tapioca`](https://github.com/Shopify/tapioca)), trigger the request that will hit the breakpoint.

### Spell Checking

VS Code users will be prompted to enable the [Code Spell Checker](https://marketplace.visualstudio.com/items?itemName=streetsidesoftware.code-spell-checker) extension.
By default this will be enabled for all workspaces, but you can choose to selectively enable or disable it per workspace.

If you introduce a word which the spell checker does not recognize, you can add it to the `cspell.json` configuration alongside your PR.

## License

The gem is available as open source under the terms of the
[MIT License](https://github.com/Shopify/ruby-lsp/blob/main/LICENSE.txt).
