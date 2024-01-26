<p align="center">
  <img alt="Ruby LSP logo" width="200" src="icon.png" />
</p>

[![Build Status](https://github.com/Shopify/vscode-ruby-lsp/workflows/CI/badge.svg)](https://github.com/Shopify/vscode-ruby-lsp/actions/workflows/ci.yml)
[![Ruby LSP extension](https://img.shields.io/badge/VS%20Code-Ruby%20LSP-success?logo=visual-studio-code)](https://marketplace.visualstudio.com/items?itemName=Shopify.ruby-lsp)
[![Ruby DX Slack](https://img.shields.io/badge/Slack-Ruby%20DX-success?logo=slack)](https://join.slack.com/t/ruby-dx/shared_invite/zt-1zjp7lmgk-zL7bGvze8gj5hFaYS~r5vg)

# Ruby LSP (VS Code extension)

The Ruby LSP is an extension that provides performant rich features for Ruby. It connects to the
[ruby-lsp](https://github.com/Shopify/ruby-lsp) language server gem to analyze Ruby code and enhance the user
experience.

Want to discuss Ruby developer experience? Consider joining the public
[Ruby DX Slack workspace](https://join.slack.com/t/ruby-dx/shared_invite/zt-1zjp7lmgk-zL7bGvze8gj5hFaYS~r5vg).

## Usage

Search for `Shopify.ruby-lsp` in the extensions tab and click install.

By default, the Ruby LSP will generate a `.ruby-lsp` directory with a custom bundle that includes the server gem.
Additionally, it will attempt to use available version managers to select the correct Ruby version for any given
project. Refer to configuration for more options.

## Features

![Ruby LSP demo](extras/ruby_lsp_demo.gif)

The Ruby LSP features include

- Semantic highlighting
- Symbol search and code outline
- RuboCop errors and warnings (diagnostics)
- Format on save (with RuboCop or Syntax Tree)
- Format on type
- [Debugging support](#configuring-vs-code-debugger)
- Running and debugging tests through VS Code's UI
- Go to definition for classes, modules, constants and required files
- Showing documentaton on hover for classes, modules and constants
- Completion for classes, modules, constants and require paths
- Fuzzy search classes, modules and constants anywhere in the project and its dependencies (workspace symbol)

Adding method support for definition, completion, hover and workspace symbol is planned, but not yet completed.

See complete information about features in the [ruby-lsp server
documentation](https://shopify.github.io/ruby-lsp/RubyLsp/Requests.html).

If you experience issues using the extension, please see the [troubleshooting
guide](https://github.com/Shopify/vscode-ruby-lsp/blob/main/TROUBLESHOOTING.md).

### Commands

Available commands are listed below and can always be found by searching for the `Ruby LSP` prefix in the command
palette (Default hotkey: CMD + SHIFT + P).

| Command                              | Description                                             |
| ------------------------------------ | ------------------------------------------------------- |
| Ruby LSP: Start                      | Start the Ruby LSP server                               |
| Ruby LSP: Restart                    | Restart the Ruby LSP server                             |
| Ruby LSP: Stop                       | Stop the Ruby LSP server                                |
| Ruby LSP: Update language server gem | Updates the `ruby-lsp` server gem to the latest version |

### Snippets

This extension provides convenience snippets for common Ruby constructs, such as blocks, classes, methods or even unit
test boilerplates. Find the full list [here](https://github.com/Shopify/vscode-ruby-lsp/blob/main/snippets.json).

### Configuration

#### Enable or disable features

The Ruby LSP allows disabling specific features. To do so, open the
language status center right next to the language mode Ruby and select `Manage` right next to enabled features.

![Ruby LSP status center](extras/ruby_lsp_status_center.png)

It's also possible to configure with more granularity code lens and inlay hint features, see the [Ruby LSP server
documentation](https://shopify.github.io/ruby-lsp/RubyLsp/Requests.html).

#### Ruby version managers

To boot the server properly, the Ruby LSP uses a version manager to activate the right environment variables that point
Bundler to the Ruby and gem paths. This is especially necessary when switching between projects that use different Ruby
versions - since those paths change and need to be reactivated.

By default, the Ruby LSP will attempt to automatically determine which version manager it should use, checking which
ones are available (`auto` option). If that fails, then the version manager must be manually configured. You can do so
by clicking `Change version manager` in the language status center or by changing your VS Code user settings.

```jsonc
// Available options are
// "auto" (select version manager automatically)
// "none" (do not use a version manager)
// "custom" (use rubyLsp.customRubyCommand for finding/activating Ruby)
// "asdf"
// "chruby"
// "rbenv"
// "rvm"
// "shadowenv"
"rubyLsp.rubyVersionManager": "chruby"
```

To make sure that the Ruby LSP can find the version manager scripts, make sure that they are loaded in the shell's
configuration script (e.g.: ~/.bashrc, ~/.zshrc) and that the SHELL environment variable is set and pointing to the
default shell.

> [!NOTE]
>
> For manager-specific notes, setting up custom activation for managers not listed above and community-contributed
> examples, please see [version managers](https://github.com/Shopify/vscode-ruby-lsp/blob/main/VERSION_MANAGERS.md).

#### Configuring a formatter

The tool to be used for formatting files can be configured with the following setting.

```jsonc
// Available options
//    auto: automatically detect the formatter based on the app's bundle (default)
//    none: do not use a formatter (disables format on save and related diagnostics)
//    all other options are the name of the formatter (e.g.: rubocop or syntax_tree)
"rubyLsp.formatter": "auto"
```

#### Ruby version requirement

By default, the Ruby LSP uses the current project's Ruby version and bundle. This allows the LSP to index the correct
gem versions, and to ensure formatting behavior is consistent with CI.

The Ruby LSP and its main dependency [Prism](https://github.com/ruby/prism) (the new Ruby parser) both follow the same
policy, which is to support only Ruby versions that are not beyond their end-of-life.

If you're working on a project with an older Ruby version, it might be possible to install older versions of the server
gem to get support for older rubies, but that might also involve using older versions of the VS Code extension - since
some functionality requires implementations in both client and server.

The other alternative is to use a custom Gemfile separate from the project with a different Ruby version. Notice that
certain functionality may be degraded or require manual configuration, since the Ruby LSP will not be able to inspect
the project's real bundle to discover dependencies. Please see the instructions below.

#### Using a custom Gemfile

If you are working on a project using an older version of Ruby not supported by Ruby LSP, then you may specify a
separate `Gemfile` for development tools.

**Note**: when using this, gems will not be installed automatically and neither will `ruby-lsp` upgrades.

Create a directory to store the custom bundle outside of the project that uses the old Ruby version. Inside that
directory, add your preferred version manager configuration to select a supported Ruby version. For example, if using
`chruby`, it would look like this:

```shell
# the/directory/.ruby-version

3.2.2
```

Create a `Gemfile` for development tools inside that directory.

```ruby
# the/directory/Gemfile
# frozen_string_literal: true

source "https://rubygems.org"

gem "ruby-lsp"
gem "rubocop"
```

> [!NOTE]
>
> Take in mind that formatters, linters and their extensions should be included in the custom gemfile; you might need to add more gems than the ones shown above.
> e.g: If you are using rubocop, you would also need to add them:

```ruby
gem "rubocop-packaging"
gem "rubocop-performance"
gem "rubocop-rspec"
gem "rubocop-shopify"
gem "rubocop-thread_safety"
```

Run `bundle install` inside that directory to generate a lockfile. After the directory contains the custom `Gemfile` and
the version manager configuration, use the following configuration in VS Code to point the Ruby LSP to that `Gemfile`.

```jsonc
{
  "rubyLsp.bundleGemfile": "../../path/to/the/directory/Gemfile",
}
```

> [!NOTE]
>
> `rubyLsp.bundleGemfile` can be a relative or absolute path.

#### Configuring VS Code debugger

To configure the VS Code debugger, you can use the "Debug: Add configuration..." command to create a `launch.json` file
in the `.vscode` directory of your project.

This command would generate the following configuration:

```jsonc
{
  "version": "0.2.0",
  "configurations": [
    {
      "type": "ruby_lsp",
      "name": "Debug",
      "request": "launch",
      "program": "ruby ${file}",
    },
    {
      "type": "ruby_lsp",
      "request": "launch",
      "name": "Debug test file",
      "program": "ruby -Itest ${relativeFile}",
    },
    {
      "type": "ruby_lsp",
      "request": "attach",
      "name": "Attach to existing server",
    },
  ],
}
```

### Debugging live processes

Instead of launching a process to debug every time, you may want to attach the VS Code debugger to an existing process, such as a Rails server. Follow these instructions to do so.

Install `debug` gem. Verify by running `bundle exec rdbg -v`

Run your application with the debugger attached, so that the extension can connect to it.

```shell
bundle exec rdbg -O -n -c -- bin/rails server -p 3000
```

For better integrated rails tests support also install `ruby-lsp-rails` gem.

#### VS Code configurations

In addition to the Ruby LSP's own configuration, there are some VS Code settings that may need to be changed to get the
most of the Ruby LSP. These settings are not specific to the Ruby LSP, but they impact all language servers and take
precedence over any other configurations.

These are the settings that may impact the Ruby LSP's behavior and their explanations.

```jsonc
{
  // All of these settings are scoped only to the Ruby language
  "[ruby]": {
    "editor.defaultFormatter": "Shopify.ruby-lsp", // Use the Ruby LSP as the default formatter
    "editor.formatOnSave": true, // Format files automatically when saving
    "editor.tabSize": 2, // Use 2 spaces for indentation
    "editor.insertSpaces": true, // Use spaces and not tabs for indentantion
    "editor.semanticHighlighting.enabled": true, // Enable semantic highlighting
    "editor.formatOnType": true, // Enable formatting while typing
  },
}
```

### Multi-root workspaces

The Ruby LSP supports multi-root workspaces by spawning a separate language server for each one of them. This strategy
is preferred over a single language server that supports multiple workspaces because each workspace could be using a
different Ruby version and completely different gems - which would be impossible to support in a single Ruby process.

Please see the [VS Code workspaces documentation](https://code.visualstudio.com/docs/editor/workspaces) on how to
configure the editor for multi-root workspaces. The Ruby LSP should work properly out of the box as long as the
workspace configuration is following the guidelines.

#### Monorepos containing multiple workspaces

A common setup is using a monorepo with directories for sub-projects. For example:

```
my_project/
  client/
  server/
```

This situation also falls under the category of multi-root workspaces. In this context, `client` and `server` are distinct
workspaces. The Ruby LSP supports this use case out of the box as long as `my_project` contains configuration that
follows [VS Code's guidelines](https://code.visualstudio.com/docs/editor/workspaces#_multiroot-workspaces) for
multi-root workspaces.

### Developing on containers

The Ruby LSP is a detached language server, which means it's a background process that runs separately from the VS Code
instance. To provide its functionality, the Ruby LSP must be running in the same place where your project files exist
and dependencies are installed.

VS Code supports connecting to containers out of the box, which makes all editor features work seamlessly. That includes
language servers, the integrated terminal, etc. The VS Code documentation has instructions on how to develop on
containers locally or remotely. Please check the following resources before opening an issue:

- [Developing inside a Container](https://code.visualstudio.com/docs/devcontainers/containers)
- [Advanced container configuration](https://code.visualstudio.com/remote/advancedcontainers/overview)

Please note that only Docker is officially supported as a backend by the Dev Container extension. <sup>[1](https://code.visualstudio.com/remote/advancedcontainers/docker-options)</sup>

## Telemetry

On its own, the Ruby LSP does not collect any telemetry by default, but it does support hooking up to a private metrics
service if desired.

In order to receive metrics requests, a private plugin must export the `ruby-lsp.getPrivateTelemetryApi` command, which
should return an object that implements the `TelemetryApi` interface defined
[here](https://github.com/Shopify/vscode-ruby-lsp/blob/main/src/telemetry.ts).

Fields included by default are defined in `TelemetryEvent`
[here](https://github.com/Shopify/vscode-ruby-lsp/blob/main/src/telemetry.ts). The exported API object can add any
other data of interest and publish it to a private service.

For example,

```typescript
// Create the API class in a private plugin
class MyApi implements TelemetryApi {
  sendEvent(event: TelemetryEvent): Promise<void> {
    // Add timestamp to collected metrics
    const payload = {
      timestamp: Date.now(),
      ...event,
    };

    // Send metrics to a private service
    myFavouriteHttpClient.post("private-metrics-url", payload);
  }
}

// Register the command to return an object of the API
vscode.commands.registerCommand(
  "ruby-lsp.getPrivateTelemetryApi",
  () => new MyApi(),
);
```

## Formatting

When `rubyLsp.formatter` is set to `auto`, Ruby LSP tries to determine which formatter to use.

If the bundle has a **direct** dependency on a supported formatter, such as `rubocop` or `syntax_tree`, that will be used.
Otherwise, formatting will be disabled and you will need add one to the bundle.

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/Shopify/vscode-ruby-lsp.
This project is intended to be a safe, welcoming space for collaboration, and contributors
are expected to adhere to the
[Contributor Covenant](https://github.com/Shopify/vscode-ruby-lsp/blob/main/CODE_OF_CONDUCT.md)
code of conduct.

Before contributing, please make sure to [sign the Contributor License Agreement](https://cla.shopify.com).

### Debugging

Interactive debugging works for both running the extension or tests. In the debug panel, select whether to run the
extension in development mode or run tests, set up some breakpoints and start with F5.

### Tracing LSP requests and responses

LSP server tracing (logging) can be controlled through the `ruby lsp.trace.server` config key in the `.vscode/settings.json`
config file.

Possible values are:

- `off`: no tracing
- `messages`: display requests and responses notifications
- `verbose`: display each request and response as JSON

### Debugging the server using VS Code

The `launch.json` contains a 'Minitest - current file' configuration for the debugger.

1. Add a breakpoint using the VS Code UI.
1. Open the relevant test file.
1. Open the **Run and Debug** panel on the sidebar.
1. Ensure `Minitest - current file` is selected in the top dropdown.
1. Press `F5` OR click the green triangle next to the top dropdown. VS Code will then run the test file with debugger activated.
1. When the breakpoint is triggered, the process will pause and VS Code will connect to the debugger and activate the debugger UI.
1. Open the Debug Console view to use the debugger's REPL.

## License

This extension is available as open source under the terms of the
[MIT License](https://github.com/Shopify/vscode-ruby-lsp/blob/main/LICENSE.txt).
