---
layout: default
title: Ruby LSP
nav_order: 0
---

# Ruby LSP

<p align="center">
  <img alt="Ruby LSP logo" width="200" src="icon.png" />
</p>

The Ruby LSP is an implementation of the [language server protocol](https://microsoft.github.io/language-server-protocol/)
for Ruby, used to improve rich features in editors. It is a part of a wider goal to provide a state-of-the-art
experience to Ruby developers using modern standards for cross-editor features, documentation and debugging.

Want to discuss Ruby developer experience? Consider joining the public
[Ruby DX Slack workspace](https://join.slack.com/t/ruby-dx/shared_invite/zt-2c8zjlir6-uUDJl8oIwcen_FS_aA~b6Q).

## Table of Contents

- [Usage](#usage)
    - [With VS Code](#with-vs-code)
    - [With other editors](#with-other-editors)
- [Addons](#addons)
- [Features](#features)
    - [Hover](#hover)
    - [Go-to-Definition](#go-to-definition)
    - [Completion](#completion)
    - [Signature Help](#signature-help)
    - [Code Navigation in `.erb` Files](#code-navigation-in-erb-files)
- [Experimental Features](#experimental-features)
    - [Ancestors Hierarchy Request](#ancestors-hierarchy-request)
    - [Guess Type](#guess-type)
- [Configuration](#configuration)
    - [Configuring code indexing](#configuring-code-indexing)
- [Additional Resources](#additional-resources)

## Usage

### With VS Code

If using VS Code, all you have to do is install the [Ruby LSP
extension](https://marketplace.visualstudio.com/items?itemName=Shopify.ruby-lsp) to get the extra features in the
editor. Do not install the `ruby-lsp` gem manually.

For more information on using and configuring the extension, see the extension's [README.md](https://github.com/Shopify/ruby-lsp/blob/main/vscode/README.md).

### With other editors

See [editors](editors) for community instructions on setting up the Ruby LSP, which current includes Emacs, Neovim, Sublime Text, and Zed.

The gem can be installed by doing

```shell
gem install ruby-lsp
```

and the language server can be launched running `ruby-lsp` (without bundle exec in order to properly hook into your
project's dependencies).

## Addons

The Ruby LSP provides an addon system that allows other gems to enhance the base functionality with more editor
features. This is the mechanism that powers addons like

- [Ruby LSP Rails](https://github.com/Shopify/ruby-lsp-rails)
- [Ruby LSP RSpec](https://github.com/st0012/ruby-lsp-rspec)
- [Ruby LSP rubyfmt](https://github.com/jscharf/ruby-lsp-rubyfmt)

Additionally, some tools may include a Ruby LSP addon directly, like

- [Standard Ruby (from v1.39.1)](https://github.com/standardrb/standard/wiki/IDE:-vscode#using-ruby-lsp)

Other community driven addons can be found in [rubygems](https://rubygems.org/search?query=name%3A+ruby-lsp) by
searching for the `ruby-lsp` prefix.

For instructions on how to create addons, see the [addons documentation](addons).

## Features

### Hover

The hover feature displays comments or documentation for the target constant or method when the cursor hovers over them.

In VS Code, if you hover while pressing `Command`, it will also send a `definition` request to locate the possible target sources. And it will display the target's source code if only one source is located (e.g., the class is not reopened in multiple places).

<video src="images/ruby-lsp-hover-demo-basic.mp4" width="100%" controls>
Sorry, your browser doesn't support embedded videos. This video demonstrates the hover feature, showing how comments and documentation are displayed for the target constant or method.
</video>

### Go-to-Definition

Go-to-definition allows users to navigate to the target constant or method's definition,
whether they're defined in your project or its dependencies.

In VS Code this feature can be triggered by one of the following methods:

- `Right click` on the target, and then select `Go to Definition`
- Placing the cursor on the target, and then hit `F12`
- `Command + click` the target

**With One Definition:**

Users are taken directly to the source.

<video src="images/ruby-lsp-definition-demo-basic.mp4" width="100%" controls>
Sorry, your browser doesn't support embedded videos. This video shows the go-to-definition feature in action, navigating directly to the source of the target constant or method.
</video>

**With Multiple Definitions:**

Users see a dropdown with all the sources, along with a preview window on the side.

<video src="images/ruby-lsp-definition-demo-multi-source.mp4" width="100%" controls>
Sorry, your browser doesn't support embedded videos. This video demonstrates the go-to-definition feature when multiple definitions are found, showing the dropdown and preview window.
</video>

### Completion

The completion feature provides users with completion candidates when the text they type matches certain indexed components. This helps speed up coding by reducing the need to type out full method names or constants.
It also allows developers to discover constants or methods that are available to them.

<video src="images/ruby-lsp-completion-demo-basic.mp4" width="100%" controls>
Sorry, your browser doesn't support embedded videos. This video illustrates the completion feature, providing completion candidates as the user types.
</video>

### Signature Help

Signature help often appears right after users finish typing a method, providing hints about the method's parameters. This feature is invaluable for understanding the expected arguments and improving code accuracy.

<video src="images/ruby-lsp-signature-help-demo-basic.mp4" width="100%" controls>
Sorry, your browser doesn't support embedded videos. This video demonstrates the signature help feature, showing hints about the parameters the target method takes.
</video>

### Code Navigation in `.erb` Files

Code navigation features, like hover, go-to-definition, completion, and signature help, are supported in `.erb` files.

<video src="images/ruby-lsp-erb-support-demo.mp4" width="100%" controls>
Sorry, your browser doesn't support embedded videos. This video illustrates the code navigation support in `.erb` files, showing the go-to-definition and hover features.
</video>

## Experimental Features

Ruby LSP also provides experimental features that are not enabled by default. If you have feedback about these features,
you can let us know in the [DX Slack](https://join.slack.com/t/ruby-dx/shared_invite/zt-2c8zjlir6-uUDJl8oIwcen_FS_aA~b6Q) or by [creating an issue](https://github.com/Shopify/ruby-lsp/issues/new).

### Ancestors Hierarchy Request

The ancestors hierarchy request feature aims to provide a better understanding of the inheritance hierarchy within your Ruby code. This feature helps developers trace the lineage of their classes and modules, making it easier to:

- Visualize the inheritance hierarchy of classes and modules.
- Quickly navigate through the inheritance chain.

<video src="images/ruby-lsp-type-hierarchy-demo.mp4" width="100%" controls>
Sorry, your browser doesn't support embedded videos. This video demonstrates the ancestors hierarchy request feature, visualizing the inheritance hierarchy.
</video>

#### Why Is It Experimental?

This feature is supported by the [Type Hierarchy Supertypes LSP request](https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/#typeHierarchy_supertypes). During implementation, we encountered some ambiguities when applying it to Ruby. For example:

- Should the list include only classes (pure inheritance chain), or should it include modules too (current behavior)?
- How should the inheritance chain of singleton classes be triggered and displayed?
- If a class or module is reopened multiple times, it will appear multiple times in the list. In real-world applications, this can make the list very long.

We created [an issue](https://github.com/microsoft/language-server-protocol/issues/1984) to seek clarification from the LSP maintainers. We will adjust this feature's design and behavior based on their response and your feedback.

### Guess Type

The guess type feature is an experimental addition to Ruby LSP that attempts to identify the type of a receiver based on its identifier name. This helps improve code completion and navigation by providing type information.

This feature is disabled by default but can be enabled with the `rubyLsp.enableExperimentalFeatures` setting in VS Code.

#### How It Works

Ruby LSP guesses the type of a variable by matching its identifier name to a class. For example, a variable named `user` would be assigned the `User` type if such a class exists:

```ruby
user.name  # Guessed to be of type `User`
@post.like!  # Guessed to be of type `Post`
```

By guessing the types of variables, Ruby LSP can expand the code navigation features to even more cases.

#### Important Notes

- Identifiers are not ideal for complex type annotations and can be easily misled by non-matching names.
- We do NOT recommend renaming identifiers just to make this feature work.

For more information, please refer to the [documentation](https://shopify.github.io/ruby-lsp/design-and-roadmap.html#guessed-types).

## Configuration

### Configuring code indexing

By default, the Ruby LSP indexes all Ruby files defined in the current project and all of its dependencies, including
default gems, except for

- Gems that only appear under the `:development` group
- All Ruby files under `test/**/*.rb`

This behaviour can be overridden and tuned. Learn how to configure it [for VS Code](https://github.com/Shopify/ruby-lsp/tree/main/vscode#indexing-configuration).

Note that indexing-dependent behavior, such as definition, hover, completion or workspace symbol will be impacted by
the configuration changes.

The older approach of using a `.index.yml` file has been deprecated and will be removed in a future release.

```yaml
# Exclude files based on a given pattern. Often used to exclude test files or fixtures
excluded_patterns:
  - "**/spec/**/*.rb"

# Include files based on a given pattern. Can be used to index Ruby files that use different extensions
included_patterns:
  - "**/bin/*"

# Exclude gems by name. If a gem is never referenced in the project's code and is only used as a tool, excluding it will
# speed up indexing and reduce the amount of results in features like definition or completion
excluded_gems:
  - rubocop
  - pathname

# Include gems by name. Normally used to include development gems that are excluded by default
included_gems:
  - prism
```

## Additional Resources

* [RubyConf 2022: Improving the development experience with language servers](https://www.youtube.com/watch?v=kEfXPTm1aCI) ([Vinicius Stock](https://github.com/vinistock))
* [Remote Ruby: Ruby Language Server with Vinicius Stock](https://remoteruby.com/221)
* [RubyKaigi 2023: Code indexing - How language servers understand our code](https://www.youtube.com/watch?v=ks3tQojSJLU) ([Vinicius Stock](https://github.com/vinistock))
