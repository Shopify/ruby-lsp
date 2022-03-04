# vscode-ruby-lsp

VS Code extension for the `ruby-lsp` gem.

## Usage

Search for `vscode-ruby-lsp` in the extensions tab and click install.

## Extension development

### Auto format

To automatically fix prettier and eslint errors on save, install the official eslint plugin and add the following configuration to your settings.json.

```json
"[typescript]": {
    "editor.codeActionsOnSave": {
        "source.fixAll.eslint": true
    },
}
```

### Debugging

Interactive debugging works for both running the extension or tests. In the debug panel, select whether to run the extension in development mode or run tests, set up some breakpoints and start with F5.

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/Shopify/vscode-ruby-lsp.
This project is intended to be a safe, welcoming space for collaboration, and contributors
are expected to adhere to the
[Contributor Covenant](https://github.com/Shopify/vscode-ruby-lsp/blob/main/CODE_OF_CONDUCT.md)
code of conduct.

## License

This extension is available as open source under the terms of the
[MIT License](https://github.com/Shopify/vscode-ruby-lsp/blob/main/LICENSE.txt).
