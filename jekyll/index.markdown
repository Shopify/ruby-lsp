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
- [General features](#general-features)
    - [Hover](#hover)
    - [Go-to-Definition](#go-to-definition)
    - [Completion](#completion)
    - [Signature Help](#signature-help)
    - [Code Lens for tests](#code-lens)
    - [Document symbol](#document-symbol)
    - [Workspace symbol](#workspace-symbol)
    - [Document link](#document-link)
    - [Document highlight](#document-highlight)
    - [Folding range](#folding-range)
    - [Semantic highlighting](#semantic-highlighting)
    - [Diagnostics](#diagnostics)
    - [Formatting](#formatting)
    - [Code actions](#code-actions)
    - [Inlay hints](#inlay-hints)
    - [On type formatting](#on-type-formatting)
    - [Selection range](#selection-range)
    - [Show syntax tree](#show-syntax-tree)
    - [ERB support](#erb-support)
- [VS Code only features](#vs-code-features)
    - [Dependencies view](#dependencies-view)
    - [Rails generator integrations](#rails-generator-integrations)
    - [Debug client](#debug-client)
    - [Version manager integrations](#version-manager-integrations)
    - [Test explorer](#test-explorer)
- [Experimental Features](#experimental-features)
    - [Ancestors Hierarchy Request](#ancestors-hierarchy-request)
    - [Guessed Types](#guessed-types)
    - [Copilot chat participant](#copilot-chat-participant)
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

## General features

{: .note }
Note that none of the features in this section are specific to Ruby; they are general to all programming languages.
Becoming familiar with them will enhance your ability to use the editor effectively.<br><br>
If you're using VS Code, we recommened their excellent [guides and documentation](https://code.visualstudio.com/docs) to
learn more about the editor's philosophy and feature set.

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

### Code Lens

Code lenses are buttons that are added automatically depending on the context of the code. The Ruby LSP supports code
lenses for unit tests, allowing you to run tests using [VS Code's test explorer](#test-explorer), run the tests in the
terminal or launch the debugger.

{: .note }
The [code
lens](https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/#textDocument_codeLens)
request requires specific commands to the implemented in the editor in order to work. For VS Code, this is included with the Ruby LSP extension. If you are using a different editor, please check the editor's documentation on how to
define the required commands.

![Code lens demo](images/code_lens.gif)

### Document symbol

Document symbol allows users to fuzzy search declarations inside the current file. It is also used to populate the
breadcrumbs and the outline.

![Document symbol demo](images/document_symbol.gif)

### Workspace symbol

Workspace symbol is the project-wide version of document symbol. It allows users to fuzzy search any declaration in the
entire project.

![Workspace symbol demo](images/workspace_symbol.gif)

### Document link

Document link makes magic `source` links clickable. This is used to connect two declarations for convenience. Note that
the links are only processed if they are immediately above a declaration and not anywhere in the code.

![Document link demo](images/document_link.gif)

### Document highlight

Document highlight reveals occurrences and declarations of the entity under the cursor.

![Document highlight demo](images/document_highlight.gif)

### Folding range

Folding range allows users to fold code at relevant ranges of the source.

![Folding range demo](images/folding_range.gif)

### Semantic highlighting

The semantic highlighting removes ambiguity from the language to achieve consistent editor highlighting. For example,
with TextMate grammars alone, local variables and method invocations with no receivers or parenthesis can be confused,
often resulting in incorrect highlighting.

The Ruby LSP's strategy for semantic highlighting is to return as few tokens as possible to ensure accurate highlighting. Processing a large number of tokens is expensive for editors and may result in lag.

{: .note }
Semantic highlighting simply informs the editor of what type of tokens exist in a file. For example, the Ruby LSP tells
the editor "this is a local variable" or "this is a method call". However, this does not mean that themes necessarily
make use of that information or that they support semantic highlighting.<br><br>
The [Ruby extensions pack extension](https://marketplace.visualstudio.com/items?itemName=Shopify.ruby-extensions-pack) includes the [Spinel](https://github.com/Shopify/vscode-shopify-ruby?tab=readme-ov-file#themes) theme, which is tailored for use with the Ruby language by fully leveraging all of Ruby LSP's semantic information.<br><br>
If you wish to add better Ruby support to other themes, see [the semantic highlighting for themes docs](semantic-highlighting).

![Semantic highlighting demo](images/semantic_highlighting.png)

### Diagnostics

Diagnostics are linting, error, warning and any other type of information that gets surfaced based on the current state
of the code. The Ruby LSP has native support for syntax errors and also supports showing linting errors.

{: .note }
You can configure which linters to use as long as they have integrations for the Ruby LSP. Check the available [configurations](editors#all-initialization-options).

![Diagnostic demo](images/diagnostic.gif)

### Formatting

Formatting allows documents to be formatted automatically on save or manually if the editor supports it.

![Formatting demo](images/formatting.gif)

### Code actions

**Quick fixes**

The Ruby LSP supports fixing violations through quick fixes.

![Quickfix demo](images/quickfix.gif)

**Refactors**

The Ruby LSP supports some code refactorings, like extract to variable, extract to method and switch block style.

![Refactors demo](images/refactors.gif)


### Inlay hints

Inlay hints display implicit information explicitly to the user. The goal is to make implicit behavior more
discoverable and visible.

By default, only implicit rescue hints are displayed. VS Code users can use the following settings to customize inlay
hint behavior:

```jsonc
{
    // Enable all hints
    "rubyLsp.featuresConfiguration.inlayHint.enableAll": true,
    // Enable implicit rescue (defaults to true)
    "rubyLsp.featuresConfiguration.inlayHint.implicitRescue": true,
    // Enable implicit hash values (omitted hash values)
    "rubyLsp.featuresConfiguration.inlayHint.implicitHashValue": true
  }
```

To configure other editors, see the [initialization options](editors#all-initialization-options).

![Inlay hint demo](images/inlay_hint.gif)

### On type formatting

On type formatting applies changes to the code as the user is typing. For example, the Ruby LSP auto completes the `end` tokens when breaking lines.

{: .note }
In VS Code, format on type is disabled by default. You can enable it with `"editor.formatOnType": true`

![On type formatting demo](images/on_type_formatting.gif)

### Selection range

Selection range (or smart ranges) expands or shrinks a selection based on the code's constructs. In VS Code, this can
be triggered with `CTRL + SHIFT + LEFT/RIGHT ARROW` to expand/shrink, respectively.

![Selection range demo](images/selection_range.gif)

### Show syntax tree

Show syntax tree displays the Abstract Syntax Tree (AST) for the current Ruby document. This custom feature can either
show the AST for the entire document or for a selection.

{: .note }
This feature is not a part of the language server specification. It is a custom feature, which is implemented in the
Ruby LSP's VS Code extension. Other editors can implement a similar approach to achieve the same functionality

![Show syntax tree demo](images/show_syntax_tree.gif)

### ERB support

The Ruby LSP can process ERB files and handle both the embedded Ruby and the host language portions of the file. For the
embedded Ruby part, the Ruby LSP responds with all Ruby features you would normally see in regular Ruby files. For
features for the host language, like HTML, the Ruby LSP delegates the requests to the language service registered to
handle that file type.

{: .note }
Request delegation has not yet been formalized as part of the LSP specification. Therefore, this requires custom code
on the client (editor) side. The Ruby LSP VS Code extension ships with that custom implementation, but other editors
will need to implement the same to support these features

{: .important }
The delegation of certain JavaScript features works partially. For example, completion inside an `onclick` attribute
will sometimes display incorrect candidates. We believe this might be a limitation of request delegation in general
and we've opened a [dicussion with VS Code](https://github.com/microsoft/vscode-discussions/discussions/1628) to better
understand it.

![ERB features demo](images/erb.gif)

## VS Code features

The following features are all custom made for VS Code.

### Dependencies view

The Ruby LSP contributes a custom dependencies view panel that allows users to navigate the dependencies of their
projects.

![Dependencies view demo](images/dependencies_view.gif)

### Rails generator integrations

The Ruby LSP integrates with Rails generators, which can be invoked through the UI. All generated files are
automatically opened and formatted using the project's formatting configurations.

![Generator demo](images/rails_generate.png)

### Debug client

The Ruby LSP ships with a client for the [debug gem](https://github.com/ruby/debug). The client allows functionality
such as [code lens](#code-lens), but also enables launch configurations for starting a process with the visual debugger
or attaching to an existing server.

### Version manager integrations

When working on many projects with different Ruby versions, the Ruby LSP needs to know which Ruby version is being used
and where gems are installed in order to support automatic dependency detection and indexing.

We support custom built integrations with the following version managers for automatic version switching with no need
for any user actions:

- [asdf](https://github.com/asdf-vm/asdf)
- [chruby](https://github.com/postmodern/chruby)
- [mise](https://github.com/jdx/mise)
- [rbenv](https://github.com/rbenv/rbenv)
- [RubyInstaller](https://rubyinstaller.org)
- [rvm](https://github.com/rvm/rvm)
- [shadowenv](https://github.com/Shopify/shadowenv)

Additionally, we provide the following escape hatches if the custom integrations are not enough:

- custom: define a custom shell script to activate the Ruby environment on any project
- none: do nothing and rely on the environment inherited by VS Code

{: .important }
Most version managers have some shell component to them in order to mutate the user's environment in a terminal and
point to the correct Ruby version. For this reason, the VS Code extension must invoke the user's shell from the NodeJS
process where it is running - otherwise the version manager wouldn't be available for the integration.<br><br>
This can sometimes lead to Ruby environment activation problems. For example, certain shell plugins expect variables
set by terminals to be present and fail if they aren't. The NodeJS process running the extension will not have set
these variables and therefore will be likely to fail.<br><br>
Finding a general solution to this problem is not trivial due to the number of different combinations of operating
systems, shells, plugins and version managers. On top of those, people configure their shell environments differently.
For example, some users may source their version managers in `~/.zshrc` while others will do it in `~/.zshenv`  or `~/.zprofile`.<br><br>
If experiencing issues, keep in mind that shell configurations could be interfering, check
[troubleshooting](troubleshooting) and, if none of the listed solutions work, please [report an issue](https://github.com/Shopify/ruby-lsp/issues/new).

### Test explorer

The Ruby LSP populates VS Code's test explorer view with the test for the current file. See [code lens](#code-lens) for
another demo.

{: .note }
The Ruby LSP intentionally does not index every single test in codebases to display in the test explorer. In large
codebases, trying to do so leads to performance issues, excessive memory usage and difficulties in navigation (due to
the amount of tests). We may reconsider this in the future, but it will require ensuring that it meets our performance
requirements

![Test explorer demo](images/test_explorer.png)

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

### Guessed Types

The guessed types feature is an experimental addition to Ruby LSP that attempts to identify the type of a receiver based on its identifier name. This helps improve code completion and navigation by providing type information.

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

### Copilot chat participant

The Ruby LSP includes a Copilot chat participant that comes with built-in knowledge of Ruby and Rails commands, helping you build these commands efficiently.

![Chat participant demo](images/chat_participant.png)


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
