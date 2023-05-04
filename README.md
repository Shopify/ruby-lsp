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

See [editors](EDITORS.md) for community instructions on setting up the Ruby LSP.

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
[Contributor Covenant](CODE_OF_CONDUCT.md)
code of conduct.

If you wish to contribute, see [CONTRIBUTING](CONTRIBUTING.md) for development instructions and check out our pinned
[roadmap issue](https://github.com/Shopify/ruby-lsp/issues/691) for a list of tasks to get started.

## License

The gem is available as open source under the terms of the
[MIT License](LICENSE.txt).
