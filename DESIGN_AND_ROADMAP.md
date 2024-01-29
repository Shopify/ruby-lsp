# Ruby LSP design and roadmap
## Design principles

These are the mental models used to make decisions in respect to the Ruby LSP.

### Favoring common development setups

There are infinite ways in which one can configure their development environment. Not only is there a vast combination
of tools that one can use (such as shells, plugins, version managers, operating systems and so on), but many tools allow
for customization to alter their default behaviors.

While there is no “right way” to use Ruby and configure the development environment, we have to draw a line somewhere in
terms of what the Ruby LSP can support. Trying to account for every different setup and customization diverts efforts
from improving the experience for the larger audience and increases the long term maintenance costs.

**Example**: the [Ruby on Rails Community survey] reports that only 2% of developers are not using a version manager to
install and configure their Ruby versions. While the popularity of each version manager varies, it’s reasonable to
consider that using a version manager is the common way of working with Ruby.

Based on this, we will always:
- Favor more common development setups and ways of working with Ruby
- Favor defaults and conventions over customization
- Aim to deliver a zero-configuration experience for common setups
- Provide flexibility where possible as long as it does not compromise the default experience

### Stability and performance over features

Adding a more complete set of editor features or improving correctness is always desired. However, we will always
prioritize the stability and the performance of Ruby LSP over adding new features.

Even if a feature is useful or if a modification improves the correctness of existing functionality, if it degrades
performance and negatively impacts the responsiveness of the editor it may actually result in a worse developer
experience.

**Example**: the Ruby syntax for constant references is ambiguous. It’s not possible to tell if a reference to `Foo` is
referring to a class, a module or a constant just based on the syntax alone. Therefore, we started the semantic
highlighting feature considering all constant references as namespaces, which is the token type available that more
closely represents the three possibilities.

To improve highlighting correctness, the Ruby LSP must resolve the references to figure out to which declaration they
point to, so that we can assign the correct token type (class, namespace or constant). However, semantic highlighting is
executed on every keypress and resolving constant references is an expensive operation - which could lead to lag in the
editor. We may decide to not correct this behavior intentionally in favor of maintaining responsiveness.

### Accuracy, correctness and type checking

The Ruby LSP does not ship with a type system. It performs static analysis with some level of type checking, but falls
back to built-in heuristics for scenarios where type annotations would be necessary.

That means that it will provide accurate results where possible and fallback to simpler behavior in situations where a
complete type system would be needed, delegating decisions to the user. Additionally, performance over features also
governs accuracy. We may prefer showing a list of options to let the user decide instead of increasing the complexity of
an implementation or degrading the overall LSP performance.

If you require more accuracy in your editor, consider adopting a type system and type checker, such as [Sorbet] or
[Steep].

This applies to multiple language server features such as go to definition, hover, completion and automated refactors.
Consider the following examples:

> [!NOTE] not all of the examples below are supported at the moment and this is not an exhaustive list. Please check the
long term roadmap to see what’s planned

```ruby
# Cases where we can provide a satisfactory experience without a type system

## Literals
"".upcase
1.to_s
{}.merge!({ a: 1 })
[].concat([])

## Scenarios where can assume the receiver type
class Foo
  def bar; end

  def baz
    bar # method invoked directly on self
  end
end

## Singleton methods with an explicit receiver
Foo.some_singleton_method

## Constant references
Foo::Bar

# Cases where a type system would be required and we fallback to heuristics to provide features

## Meta-programming
Foo.define_method("some#{interpolation}") do |arg|
end

## Methods invoked on the return values of other methods
## Not possible to provide accurate features without knowing the return type
## of invoke_foo
var = invoke_foo
var.upcase # <- not accurate

## Same thing for chained method calls
## To know where the definition of `baz` is, we need to know the return type
## of `foo` and `bar`
foo.bar.baz
```

**Example**: when using refactoring features you may be prompted to confirm a code modification as it could be
incorrect. Or when trying to go to the definition of a method, you may be prompted with all declarations that match the
method call’s name and arguments instead of jumping to the correct one directly.

As another fallback mechanism, we want to explore using variable or method call names as a type hint to assist accuracy
(not yet implemented). For example

```ruby
# Typically, a type annotation for `find` would be necessary to discover
# that the type of the `user` variable is `User`, allowing the LSP to
# find the declaration of `do_something`.
#
# If we consider the variable name as a snake_case version of its type
# we may be able to improve accuracy and deliver a nicer experience even
# without the adoption of a type system
user = User.find(1)
user.do_something
```

### Extensibility

In an effort to reduce tooling fragmentation in the Ruby ecosystem, we are experimenting with an addon system for the
Ruby LSP server. This allows other gems to enhance the Ruby LSP’s functionality without having to write a complete
language server of their own, avoiding handling text synchronization, implementing features that depend exclusively on
syntax (such as folding range) or caring about the editor’s encoding.

We believe that a less fragmented tooling ecosystem leads to a better user experience that requires less configuration
and consolidates efforts from the community.

Our goal is to allow the Ruby LSP to connect to different formatters, linters, type checkers or even extract runtime
information from running applications like Rails servers. You can learn more in the [addons documentation](ADDONS.md).

### Relying on Bundler

Understanding the dependencies of projects where the Ruby LSP is being used on allows it to provide a zero configuration
experience to users. It can automatically figure out which gems have to be indexed to provide features like go to
definition or completion. That also allows it to connect to the formatter/linter being used, without asking for any
configuration.

To make that work, the Ruby LSP relies on Bundler, Ruby’s official dependency manager. This decision allows the LSP to
easily get information about dependencies, but it also means that it is subject to how Bundler works.

**Example**: gems need to be installed on the Ruby version used by the project for the Ruby LSP to find it (bundle
install needs to be satisfied). It needs to be the same Ruby version because otherwise Bundler might resolve to a
different set of versions for those dependencies, which could result in failure to install due to version constraints or
the LSP indexing the incorrect version of a gem (which could lead to surfacing constants that do not exist in the
version used by the project).

**Example**: if we tried to run the Ruby LSP without the context of the project’s bundle, then we would not be able to
require gems from it. Bundler only adds dependencies that are part of the current bundle to the load path. Ignoring the
project’s bundle would make the LSP unable to require tools like RuboCop and its extensions.

Based on this, we will always:
- Rely on Bundler to provide dependency information
- Focus our efforts on Bundler integrations and helping improve Bundler itself
- Only support other dependency management tools if it does not compromise the default experience through Bundler

## Long term roadmap

The goal of this roadmap is to bring visibility into what we have planned for the Ruby LSP. This is not an exhaustive
task list, but rather large milestones we wish to achieve.

Please note that there are no guarantees about the order in which entries will be implemented or if they will be
implemented at all given that we may uncover blockers along the way.

Interested in contributing? Check out the issues tagged with [help-wanted] or [good-first-issue].

- [Make Ruby environment activation more flexible and less coupled with shells]
- Stabilize APIs for Ruby LSP addons to allow other gems to enhance the base features
- [Full method support for definition, hover and completion]
- [Improve accuracy of method features by handling class/module hierarchies]
- [Improve accuracy of test code lens by checking which class a method inherits from]
- Explore using variable/method call names as a type hint
- [Develop strategy to index declarations made in native extensions or C code. For example, Ruby’s own Core classes]
- [Add find references support]
- [Add rename support]
- [Add show type hierarchy support]
- [Show index view on the VS Code extension allowing users to browse indexed gems]
- Remove custom bundle in favor of using bundler-compose
- [Add more refactoring code actions such as extract to method, extract to class/module, etc]
- [Explore speeding up indexing by caching the index for gems]
- Explore speeding up indexing by making Prism AST allocations lazy
- [Add range formatting support for formatters that do support it]
- [Add ERB support]
- Explore allowing addons to add support for arbitrary file types
- Allow the Ruby LSP to connect to a typechecker addon to improve accuracy
- Make the Ruby LSP’s default functionality act as a fallback for the more accurate typechecker results

[Ruby on Rails Community survey]: https://rails-hosting.com/2022/#ruby-rails-version-updates
[Sorbet]: https://sorbet.org/
[Steep]: https://github.com/soutaro/steep
[help-wanted]: https://github.com/Shopify/ruby-lsp/issues?q=is%3Aopen+is%3Aissue+label%3Ahelp-wanted
[good-first-issue]: https://github.com/Shopify/ruby-lsp/issues?q=is%3Aopen+is%3Aissue+label%3Agood-first-issue
[Make Ruby environment activation more flexible and less coupled with shells]: https://github.com/Shopify/vscode-ruby-lsp/pull/923
[Full method support for definition, hover and completion]: https://github.com/Shopify/ruby-lsp/issues/899
[Improve accuracy of method features by handling class/module hierarchies]: https://github.com/Shopify/ruby-lsp/issues/1333
[Improve accuracy of test code lens by checking which class a method inherits from]: https://github.com/Shopify/ruby-lsp/issues/1334
[Develop strategy to index declarations made in native extensions or C code. For example, Ruby’s own Core classes]: https://github.com/Shopify/ruby-lsp/issues/1335
[Add find references support]: https://github.com/Shopify/ruby-lsp/issues/202
[Add rename support]: https://github.com/Shopify/ruby-lsp/issues/57
[Add show type hierarchy support]: https://github.com/Shopify/ruby-lsp/issues/1046
[Show index view on the VS Code extension allowing users to browse indexed gems]: https://github.com/Shopify/vscode-ruby-lsp/pull/464
[Add more refactoring code actions such as extract to method, extract to class/module, etc]: https://github.com/Shopify/ruby-lsp/issues/60
[Explore speeding up indexing by caching the index for gems]: https://github.com/Shopify/ruby-lsp/issues/1009
[Add range formatting support for formatters that do support it]: https://github.com/Shopify/ruby-lsp/issues/203
[Add ERB support]: https://github.com/Shopify/ruby-lsp/issues/1055
