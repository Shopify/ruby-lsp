---
layout: default
title: Custom Ruby LSP bundle
nav_order: 40
parent: Ruby LSP
---

# Custom Ruby LSP bundle

In language ecosystems other than Ruby, it is not super common to have to add editor tooling as part of your project
dependencies. Usually, a language server is an executable that gets downloaded and then run independently from your
projects.

In the Ruby ecosystem, there are a few blockers to fully adopting this approach:

1. Not writing the language server in Ruby would make it challenging to integrate seamlessly with existing tools used by
the community that are already written in Ruby, like test frameworks, linters, formatters and so on
2. Discovering project dependencies automatically allows the language server to detect which files on disk must be read
and indexed, so that we can extract declarations from gems without requiring any configuration from the user. This means
that we need to integrate directly with Bundler
3. Bundler only allows requiring gems that are set up as part of the `$LOAD_PATH`. If the Ruby LSP executable was running
independently from a global installation, then the Ruby process would only be able to require the Ruby LSP's own
dependencies, but it would not be able to require any gems used by the project being worked on. Not being able to require
the project's dependencies limits integrations that the language server can automatically make with linters, formatters,
test frameworks and so on

To overcome these limitations, while at the same time not requiring users to add `ruby-lsp` as a dependency of their projects,
the Ruby LSP uses a custom bundle strategy. The flow of execution is as follows:

1. The executable is run as `ruby-lsp` without `bundle exec` to indicate that the custom bundle must first be configured
2. The executable sets up a custom bundle under `your_project/.ruby-lsp`. The generated Gemfile includes the `ruby-lsp` gem
and everything in the project's Gemfile as well. It may also include `debug` and `ruby-lsp-rails`
3. After the custom bundle is fully set up, then the original `ruby-lsp` Ruby process is fully replaced by
`BUNDLE_GEMFILE=.ruby-lsp/Gemfile bundle exec ruby-lsp`, thus launching the real language server with access to the project's
dependencies, but without requiring adding the gem to the project's own Gemfile

In addition to performing this setup, the custom bundle logic will also `bundle install` and attempt to auto-update the
`ruby-lsp` language server gem to ensure fast distribution of bug fixes and new features.

{: .note }
Setting up the custom bundle requires several integrations with Bundler and there are many edge cases to consider, like
how to handle configurations or installing private dependencies. If you encounter a problem with the custom bundle
setup, please let us know by [reporting an issue](https://github.com/Shopify/ruby-lsp/issues/new).
