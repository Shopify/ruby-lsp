---
layout: default
title: Security
nav_order: 25
---

# Security

This page documents potential risks when using the Ruby LSP VS Code extension and the Ruby LSP language server with untrusted code.

## Trust Model

**Ruby LSP assumes that all code in your workspace is trusted.**

When you open a project with Ruby LSP, the extension and language server will execute code from that project as part of
normal operation. This is fundamentally similar to running `bundle install` in that project directory.

If you are working with code you do not fully trust, you should be aware of the potential risks documented below.

## Code Execution Vectors

The following is a non-exhaustive list of ways that Ruby LSP may execute code from your workspace:

### Bundle Installation

Ruby LSP automatically performs bundler operations (e.g. `bundle install`, `bundle update`) when starting up or when detecting changes to your
Gemfile. This will:

- Execute any code in your Gemfile (Gemfiles are Ruby code)
- Install gems specified in the Gemfile, which may include native extensions that execute during installation
- Run any post-install hooks defined by gems

### Add-ons / Plugins

Ruby LSP has an add-on system that automatically discovers and loads add-ons from:

- Gems in your bundle that contain `ruby_lsp/**/addon.rb` files
- Files matching `ruby_lsp/**/addon.rb` anywhere in your workspace

Add-ons are loaded via `require` and their `activate` method is called, allowing them to execute arbitrary Ruby code.
This is by design - add-ons can spawn processes, make network requests, or perform any other operation.

## Recommendations

1. **Understand what "Trust" means** - Trusting a project with Ruby LSP installed is equivalent to feeling comfortable running `bundle install` in that directory.
2. **Understand [VS Code's Workspace Trust](https://code.visualstudio.com/docs/editor/workspace-trust)** - When opening unfamiliar projects, click "Don't Trust" on the workspace trust prompt.
   Ruby LSP will not run in untrusted workspaces, eliminating any risk.
3. **Be cautious with unfamiliar add-ons** - Add-ons have full access to your system when activated.

## Reporting Security Issues

If you discover a security vulnerability in Ruby LSP, please report it through
[GitHub Security Advisories](https://github.com/Shopify/ruby-lsp/security/advisories/new) rather than opening a public
issue.
