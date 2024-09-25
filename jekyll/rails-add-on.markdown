---
layout: default
title: Rails add-on
nav_order: 10
---

# Rails add-on

[Ruby LSP Rails](https://github.com/Shopify/ruby-lsp-rails) is a Ruby LSP add-on that enhances the base Ruby LSP functionality
with Rails-specific features. It provides improved code navigation, document symbols for Rails-specific elements,
and runtime introspection capabilities.

It [communicates with a running Rails instance](#runtime-introspection) to provide dynamic information about the application,
enabling more accurate and context-aware language server features.

## Table of Contents

- [Installation](#installation)
- [Runtime Introspection](#runtime-introspection)
- [Features](#features)
    - [**Document Symbol**](#document-symbol)
        - [Active Record Callbacks, Validations, and Associations](#active-record-callbacks-validations-and-associations)
        - [Active Support Test Cases](#active-support-test-cases)
    - [**Go to Controller Action Route**](#go-to-controller-action-route)
    - [**Go to Controller Action View**](#go-to-controller-action-view)
    - [**Go to Definition**](#go-to-definition)
        - [Go to Active Record Callback and Validation Definitions](#go-to-active-record-callback-and-validation-definitions)
        - [Go to Active Record Associations](#go-to-active-record-associations)
        - [Go to Route Helper Definitions](#go-to-route-helper-definitions)
    - [**Ruby File Operations**](#ruby-file-operations)
        - [Commands](#commands)
    - [**Run and Debug**](#run-and-debug)
        - [Run Tests With Test Explorer](#run-tests-with-test-explorer)
        - [Run Tests In The Terminal](#run-tests-in-the-terminal)
        - [Debug Tests With VS Code](#debug-tests-with-vs-code)

## Installation

{: .important }
> The Rails add-on is installed automatically.

Ruby LSP detects Rails projects and installs the [Rails add-on](https://github.com/Shopify/ruby-lsp-rails) for you.

## Runtime Introspection

LSP tooling is typically based on static analysis, but `ruby-lsp-rails` actually communicates with your Rails app for
some features.

When Ruby LSP Rails starts, it spawns a `rails runner` instance which runs
[`server.rb`](https://github.com/Shopify/ruby-lsp-rails/blob/main/lib/ruby_lsp/ruby_lsp_rails/server.rb).
The add-on communicates with this process over a pipe (i.e. `stdin` and `stdout`) to fetch runtime information about the application.

When extension is stopped (e.g. by quitting the editor), the server instance is shut down.

## Features

### **Document Symbol**

Document Symbol is a way to represent the structure of a document. They are used to provide a quick overview of the
document and to allow for quick navigation.

Ruby LSP already provides document symbols for Ruby files, such as classes, modules, methods, etc. But the Rails add-on
provides additional document symbols for Rails specific features.

In VS Code, you can open the document symbols view by pressing `Ctrl + Shift + O`.

### Active Record Callbacks, Validations, and Associations

Navigates between Active Record callbacks, validations, and associations using the `Document Symbol` feature.

![Document Symbol for Active Record Callbacks, Validations, and Associations](images/ruby-lsp-rails-document-symbol-ar-model.gif)

### Active Support Test Cases

Navigates between Active Support test cases using the `Document Symbol` feature.

![Document Symbol for tests](images/ruby-lsp-rails-test-document-symbol.gif)

### **Go to Controller Action Route**

Navigates to the route definition of a controller action using the `Code Lens` feature.

![Go to Controller Action Route](images/ruby-lsp-rails-controller-action-to-route.gif)

### **Go to Controller Action View**

Navigates to the view file(s) of a controller action using the `Code Lens` feature.

![Go to Controller Action View](images/ruby-lsp-rails-controller-action-to-view.gif)

### **Go to Definition**

Go to definition is a feature that allows you to navigate to the definition of a symbol.

In VS Code, you can trigger go to definition in 3 different ways:

- Select `Go to Definition` from the context menu
- `F12` on a symbol
- `Cmd + Click` on a symbol

In the following demos, we will use the `Cmd + Click` method to trigger go to definition.

### Go to Active Record Callback and Validation Definitions

Navigates to the definitions of Active Record callbacks and validations.

![Go to Active Record Callback and Validation Definitions](images/ruby-lsp-rails-go-to-ar-dsl-definitions.gif)

### Go to Active Record Associations

Navigates to the definitions of Active Record associations.

![Go to Active Record Associations](images/ruby-lsp-rails-go-to-ar-associations.gif)

### Go to Route Helper Definitions

![Go to Route Helper Definitions](images/ruby-lsp-rails-go-to-route-definitions.gif)

### **Ruby File Operations**

The Ruby LSP extension provides a `Ruby file operations` icon in the Explorer view that can be used to trigger
the `Rails generate` and `Rails destroy` commands.

![Ruby file operations](images/ruby-lsp-rails-file-operations-icon.gif)

### Commands

These commands are also available in the Command Palette.

#### Rails Generate

![Rails Generate](images/ruby-lsp-rails-generate-command.gif)

#### Rails Destroy

![Rails Destroy](images/ruby-lsp-rails-destroy-command.gif)

### **Run and Debug**

The Rails add-on provides 3 ways to run and debug `ActiveSupport` tests using the `Code Lens` feature.

### Run Tests With Test Explorer

![Run Tests With Test Explorer](images/ruby-lsp-rails-run.gif)

### Run Tests In The Terminal

![Run Tests In The Terminal](images/ruby-lsp-rails-run-in-terminal.gif)

### Debug Tests With VS Code

![Debug Tests With VS Code](images/ruby-lsp-rails-debug.gif)
