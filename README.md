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

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/Shopify/ruby-lsp.
This project is intended to be a safe, welcoming space for collaboration, and contributors
are expected to adhere to the
[Contributor Covenant](https://github.com/Shopify/ruby-lsp/blob/main/CODE_OF_CONDUCT.md)
code of conduct.

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
