---
layout: default
title: Editors
nav_order: 0
parent: Ruby LSP
---

# Editors

This file contains community driven instructions on how to set up the Ruby LSP in editors other than VS Code. For VS
Code, use the official [Ruby LSP extension](https://marketplace.visualstudio.com/items?itemName=Shopify.ruby-lsp).

{: .note }
> Some Ruby LSP features may be unavailable or limited due to incomplete implementations of the Language Server
> Protocol, such as dynamic feature registration, or [file watching](https://github.com/Shopify/ruby-lsp/issues/1456).

If you wish to enable or disable features or configure other aspects of the language server, see [initialization options](#all-initialization-options).

{: .important }
> The command to launch the language server might depend on which editor and version manager combination you are using.
> In order to work properly, the Ruby LSP must be launched with the Ruby version being used by the project you are working
> on and with the correct Bundler environment set.

If you normally launch your editor from the terminal in a shell session where the Ruby environment is already activated,
then you can probably just use `ruby-lsp` as the command.

If you're seeing issues related to not finding the right gems or not being able to locate the `ruby-lsp` executable,
then you may need to ensure that the environment is properly configured by the version manager before you try to run the
`ruby-lsp` executable. How to do this will depend on which version manager you use. Here are some examples:

If your version manager exposes a command to run an executable within the context of the current Ruby, use that:

- `mise x -- ruby-lsp`
- `shadowenv exec -- ruby-lsp`

If your version manager creates gem executable shims that perform the automatic version switching, then use those:

- `~/.rbenv/shims/ruby-lsp`
- `~/.asdf/shims/ruby-lsp`

If your version manager doesn't provide either of those, then activate the environment and run the executable:

- `chruby $(cat .ruby-version) && ruby-lsp`

These strategies will ensure that the `ruby-lsp` executable is invoked with the correct Ruby version, `GEM_HOME` and
`GEM_PATH`, which are necessary for proper integration with your project.

## All initialization options

Each LSP client can control various abilities of the LSP at startup. The following JSON dictionary contains all of the
available initialization options. Generally, editor LSP clients will configure LSP servers using a dictionary in their
configuration languages (JSON, Lua, ELisp, etc.).

```json
{
  "initializationOptions": {
    "enabledFeatures": {
      "codeActions": true,
      "codeLens": true,
      "completion": true,
      "definition": true,
      "diagnostics": true,
      "documentHighlights": true,
      "documentLink": true,
      "documentSymbols": true,
      "foldingRanges": true,
      "formatting": true,
      "hover": true,
      "inlayHint": true,
      "onTypeFormatting": true,
      "selectionRanges": true,
      "semanticHighlighting": true,
      "signatureHelp": true,
      "typeHierarchy": true,
      "workspaceSymbol": true
    },
    "featuresConfiguration": {
      "inlayHint": {
        "implicitHashValue": true,
        "implicitRescue": true
      }
    },
    "indexing": {
      "excludedPatterns": ["path/to/excluded/file.rb"],
      "includedPatterns": ["path/to/included/file.rb"],
      "excludedGems": ["gem1", "gem2", "etc."],
      "excludedMagicComments": ["compiled:true"]
    },
    "formatter": "auto",
    "linters": [],
    "experimentalFeaturesEnabled": false
  }
}
```

<!-- When adding a new editor to the list, either link directly to a website containing the instructions or link to a
new H2 header in this file containing the instructions. -->

- [Emacs LSP Mode](https://emacs-lsp.github.io/lsp-mode/page/lsp-ruby-lsp/)
- [Emacs Eglot](#emacs-eglot)
- [Neovim LSP](#neovim)
- [LazyVim LSP](#lazyvim-lsp)
- [Sublime Text LSP](#sublime-text-lsp)
- [Zed](#zed)
- [RubyMine](#rubymine)
- [Kate](#kate)
- [Helix](#helix)

## Emacs Eglot

[Eglot](https://github.com/joaotavora/eglot) runs solargraph server by default. To set it up with ruby-lsp you need to
put that in your init file:
```el
(with-eval-after-load 'eglot
 (add-to-list 'eglot-server-programs '((ruby-mode ruby-ts-mode) "ruby-lsp")))
 ```

When you run `eglot` command it will run `ruby-lsp` process for you.

## Neovim

**Note**: Ensure that you are using Neovim 0.10 or newer.

### nvim-lspconfig

The [nvim-lspconfig](https://github.com/neovim/nvim-lspconfig/blob/master/lua/lspconfig/configs/ruby_lsp.lua) plugin has
support for Ruby LSP.

The Ruby LSP can be configured using the `init_options` key when setting up the LSP.

A great example of this configuration style is enabling the Standard add-on for
the Ruby LSP to enable formatting and pull-style diagnostics. The following snippet
enables `standard` for both formatting and pull-diagnostic linting.

```lua
local lspconfig = require('lspconfig')
lspconfig.ruby_lsp.setup({
  init_options = {
    formatter = 'standard',
    linters = { 'standard' },
  },
})
```

### Mason

You can use [mason.nvim](https://github.com/williamboman/mason.nvim),
along with [mason-lspconfig.nvim](https://github.com/williamboman/mason-lspconfig.nvim):

```lua
local capabilities = vim.lsp.protocol.make_client_capabilities()
local mason_lspconfig = require("mason-lspconfig")
local servers = {
  ruby_lsp = {},
}

mason_lspconfig.setup {
  ensure_installed = vim.tbl_keys(servers),
}

mason_lspconfig.setup_handlers {
  function(server_name)
    require("lspconfig")[server_name].setup {
      capabilities = capabilities,
      on_attach = on_attach,
      settings = servers[server_name],
      filetypes = (servers[server_name] or {}).filetypes,
    }
  end
}
```

{: .important }
> Using Mason to manage your installation of the Ruby LSP may cause errors

Mason installs the Ruby LSP in a folder shared among all your Rubies. Some of the
Ruby LSP dependencies are C extensions, and they rely on the Ruby ABI to look and
act a certain way when they were linked to Ruby. This causes issues when a shared
folder is used.

See [this issue][mason-abi] for further information.

### Additional setup (optional)

`rubyLsp/workspace/dependencies` is a custom method currently supported only in the VS Code plugin.
The following snippet adds `ShowRubyDeps` command to show dependencies in the quickfix list.

```lua
local function add_ruby_deps_command(client, bufnr)
  vim.api.nvim_buf_create_user_command(bufnr, "ShowRubyDeps", function(opts)
    local params = vim.lsp.util.make_text_document_params()
    local showAll = opts.args == "all"

    client.request("rubyLsp/workspace/dependencies", params, function(error, result)
      if error then
        print("Error showing deps: " .. error)
        return
      end

      local qf_list = {}
      for _, item in ipairs(result) do
        if showAll or item.dependency then
          table.insert(qf_list, {
            text = string.format("%s (%s) - %s", item.name, item.version, item.dependency),
            filename = item.path
          })
        end
      end

      vim.fn.setqflist(qf_list)
      vim.cmd('copen')
    end, bufnr)
  end,
  {nargs = "?", complete = function() return {"all"} end})
end

require("lspconfig").ruby_lsp.setup({
  on_attach = function(client, buffer)
    add_ruby_deps_command(client, buffer)
  end,
})
```

## LazyVim LSP

[As of v12.33.0](https://github.com/LazyVim/LazyVim/pull/3652), Ruby LSP is the default LSP for Ruby.

To ensure the correct Ruby version is selected, we recommend disabling the `mason` option and specifying the
appropriate command for your Ruby version manager as an absolute path. For example:

```lua
return {
  {
    "neovim/nvim-lspconfig",
    opts = {
      servers = {
        ruby_lsp = {
          mason = false,
          cmd = { vim.fn.expand("~/.asdf/shims/ruby-lsp") },
        },
      },
    },
  },
}

```

## Sublime Text LSP

To configure the Ruby LSP using [LSP for Sublime Text](https://github.com/sublimelsp/LSP), add the following configuration to your LSP client configuration:

```json
"clients": {
  "ruby-lsp": {
    "enabled": true,
    "command": [
      "ruby-lsp"
    ],
    "selector": "source.ruby",
    "initializationOptions": {
      "enabledFeatures": {
        "diagnostics": false
      },
      "experimentalFeaturesEnabled": true
    }
  }
}
```

Restart LSP or Sublime Text and `ruby-lsp` will automatically activate when opening ruby files.

## Zed

[Setting up Ruby LSP](https://github.com/zed-industries/zed/blob/main/docs/src/languages/ruby.md#setting-up-ruby-lsp)

[Zed has added support for Ruby LSP as a alternative language server](https://github.com/zed-industries/zed/pull/11768) in version v0.0.2 of the Ruby extension.

See https://github.com/zed-industries/zed/issues/4834 for discussion of the limitations.

## RubyMine

You can use the Ruby LSP with RubyMine (or IntelliJ IDEA Ultimate) through the following plugin.

Note that there might be overlapping functionality when using it with RubyMine, given that the IDE provides similar features as the ones coming from the Ruby LSP.

[Ruby LSP plugin](https://plugins.jetbrains.com/plugin/24413-ruby-lsp)

## Kate

[The LSP Client Plugin](https://docs.kde.org/stable5/en/kate/kate/kate-application-plugin-lspclient.html) for Kate is configured by default to use Solargraph for Ruby.
To use it with Ruby LSP, you can override particular configuration items in the "User Server Settings" in the LSP Client plugin as shown below:

```json
{
  "servers": {
    "ruby": {
      "command": ["ruby-lsp"],
      "url": "https://github.com/Shopify/ruby-lsp"
    }
  }
}
```

Kate will start an instance of the Ruby LSP server in the background for any Ruby project matching the `rootIndicationFileNames`.
If starting Ruby LSP succeeds, the entries in the LSP-Client menu are activated.
Otherwise the error output can be inspected in the Output window.

## Helix

To configure the Ruby LSP in helix you first need to define it as a language server and then set it as the main LSP for ruby.
This will also set ruby-lsp to be used as a formatter with its built-in rubocop integration.

```toml
# languages.toml

[language-server.ruby-lsp]
command = "ruby-lsp"
config = { diagnostics = true, formatting = true }

[[language]]
name = "ruby"
language-servers = ["ruby-lsp"]
auto-format = true
```

[mason-abi]: https://github.com/williamboman/mason.nvim/issues/1292
