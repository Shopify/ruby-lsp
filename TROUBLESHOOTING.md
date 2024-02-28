# Troubleshooting

## How the Ruby LSP activation works

The Ruby LSP extension runs inside VS Code's NodeJS runtime, like any other VS Code extension. This means that
environment variables that are properly set in your shell may not exist inside the NodeJS process. To run the LSP server
with the same Ruby version as your projects, we need to properly set these environment variables, which is done by
invoking your Ruby version manager.

The extension runs a command using your shell's interactive mode, so that version managers configured in files such as
`~/.zshrc` are picked up automatically. The command then exports the environment information into JSON, so that we can
inject it into the NodeJS process and appropriately set the Ruby version and gem installation paths.

As an example, the activation script for `zsh` using `rbenv` as a version manager will look something like this:

```shell
# Invoke zsh using interactive mode (loads ~/.zshrc) to run a single command
# The command is `rbenv exec ruby`, which automatically sets all relevant environment variables and selects the
# specified Ruby version
# We then print the activated environment as JSON. We read that JSON from the NodeJS process to insert the needed
# environment variables in order to run Ruby correctly
/bin/zsh -ic 'rbenv exec ruby -rjson -e "puts JSON.dump(ENV.to_h)"'
```

After activating the Ruby version, we then proceed to boot the server gem (`ruby-lsp`). To avoid having users include
the `ruby-lsp` in their `Gemfile`, we currently create a custom bundle under the `.ruby-lsp` directory inside your
project. That directory contains another `Gemfile`, that includes the `ruby-lsp` gem in addition to your project's
dependencies. This approach allows us to automatically detect which formatter your project uses and which gems we need
to index for features such as go to definition.

> **Note**: we are working with the rubygems/bundler team to have this type of mechanism properly supported from within
> Bundler itself, which is currently being experimented with in a plugin called `bundler-compose`. Once
> `bundler-compose`is production ready, the entire custom bundle created under the `.ruby-lsp` directory will go away
> and we'll rely on Bundler to compose the LOAD_PATH including the `ruby-lsp` gem.

## Common issues

There are two main sources of issues users typically face during activation: shell or Bundler related problems.

### Shell issues

When the extension invokes the shell and loads its config file (`~/.zshrc`, `~/.bashrc`, etc), it is susceptible to
issues that may be caused by how the shell or its plugins interact with the NodeJS process. For example

- Some plugins completely redirect the stderr pipe to implement their functionality (fixed on the Ruby LSP side by
  https://github.com/Shopify/vscode-ruby-lsp/pull/918)
- Some plugins fail immediately or end up in an endless loop if they detect there's no UI attached to the shell process.
  In this case, it's not possible to fix from the Ruby LSP side since a shell invoked by NodeJS will never have a UI

Additionally, some users experience an issue where VS Code selects the wrong shell, not respecting the `SHELL`
environment variable. This usually ends up in having `/bin/sh` selected instead of your actual shell. If you are facing
this problem, please try to

- Update VS Code to the latest version
- Completely close VS Code and launch it from the terminal with `code .` (instead of opening VS Code from the launch
  icon)

More context about this issue on https://github.com/Shopify/vscode-ruby-lsp/issues/901.

### Bundler issues

If the extension successfully activated the Ruby environment, it may still fail when trying to compose the custom bundle
to run the server gem. This could be a regular Bundler issue, like not being able to satisfy dependencies due to a
conflicting version requirement, or it could be a configuration issue.

For example, if the project has its linter/formatter put in an optional `Gemfile` group and that group is excluded in
the Bundler configuration, the Ruby LSP will not be able to see those gems.

```ruby
# Gemfile

# ...

# If Bundler is configured to exclude this group, the Ruby LSP will not be able to find `rubocop`
group :optional_group do
  gem "rubocop"
end
```

If you experience Bundler related issues, double-check both your global and project-specific configuration to check if
there's anything that could be preventing the server from booting. You can print your Bundler configuration with

```shell
bundle config
```

### Format on save dialogue won't disappear

When VS Code requests formatting for a document, it opens a dialogue showing progress a couple of seconds after sending
the request, closing it once the server has responded with the formatting result.

If you are seeing that the dialogue is not going away, this likely doesn't mean that formatting is taking very long or
hanging. It likely means that the server crashed or got into a corrupt state and is simply not responding to any
requests, which means the dialogue will never go away.

This is always the result of a bug in the server. It should always fail gracefully without getting into a corrupt state
that prevents it from responding to new requests coming from the editor. If you encounter this, please submit a bug
report [here](https://github.com/Shopify/ruby-lsp/issues/new?labels=bug&template=bug_template.yml) including the
steps that led to the server getting stuck.

### Developing on containers

See the [documentation](README.md#developing-on-containers).

## Diagnosing the problem

Many activation issues are specific to how your development environment is configured. If you can reproduce the problem
you are seeing, including information about these steps is the best way to ensure that we can fix the issue in a timely
manner. Please include the steps taken to diagnose in your bug report.

### Check if the server is running

Check the [status center](https://github.com/Shopify/ruby-lsp/blob/main/extras/ruby_lsp_status_center.png).
Does the server status say it's running? If it is running, but you are missing certain features, please check our
[documentation](https://shopify.github.io/ruby-lsp/RubyLsp/Requests.html) to ensure we already added support for it.

If the feature is listed as fully supported, but not working for you, report [an
issue](https://github.com/Shopify/ruby-lsp/issues/new?labels=bug&projects=&template=bug_template.yml) so that we can
assist.

### Check the VS Code output tab

Many of the activation steps taken are logged in the `Ruby LSP` channel of VS Code's `Output` tab. Check the logs to see
if any entries hint at what the issue might be. Did the extension select your preferred shell?

Did it select your preferred version manager? You can define which version manager to use with the
`"rubyLsp.rubyVersionManager"` setting.

### My preferred version manager is not supported

We default to supporting the most common version managers, but that may not cover every single tool available. For these
cases, we offer custom activation support. More context in the version manager
[documentation](https://github.com/Shopify/ruby-lsp/blob/main/vscode/VERSION_MANAGERS.md).

### Try to run the Ruby activation manually

If the extension is failing to activate the Ruby environment, try running the same command manually in your shell to see
if the issue is exclusively related with the extension. The exact command used for activation is printed to the output
tab.

### Try booting the server manually

If the Ruby environment seems to activate properly, but the server won't boot, try to launch is manually from the
terminal with

```shell
# Do not use bundle exec
ruby-lsp
```

Is there any extra information given from booting the server manually? Or does it only fail when booting through the
extension?

## After troubleshooting

If after troubleshooting the Ruby LSP is still not initializing properly, please report an issue
[here](https://github.com/Shopify/ruby-lsp/issues/new?labels=bug&template=bug_template.yml) so that we can assist
in fixing the problem. Remember to include the steps taken when trying to diagnose the issue.
