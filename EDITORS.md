# Editors

This file contains community driven instructions on how to set up the Ruby LSP in editors other than VS Code. For VS
Code, use the official [Ruby LSP extension](https://marketplace.visualstudio.com/items?itemName=Shopify.ruby-lsp).

> [!NOTE]
> Some Ruby LSP features may be unavailable or limited due to incomplete implementations of the Language Server
> Protocol, such as dynamic feature registration, or [file watching](https://github.com/Shopify/ruby-lsp/issues/1456).

If you need to select particular features to enable or disable, see
[`vscode/package.json`](vscode/package.json) for the full list.

<!-- When adding a new editor to the list, either link directly to a website containing the instructions or link to a
new H2 header in this file containing the instructions. -->

- [Emacs LSP Mode](https://emacs-lsp.github.io/lsp-mode/page/lsp-ruby-lsp/)
- [Emacs Eglot](#Emacs-Eglot)
- [Neovim LSP](#Neovim)
- [LazyVim LSP](#lazyvim-lsp)
- [Sublime Text LSP](#sublime-text-lsp)
- [Zed](#zed)
- [RubyMine](#RubyMine)

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

The [nvim-lspconfig](https://github.com/neovim/nvim-lspconfig/blob/master/lua/lspconfig/server_configurations/ruby_lsp.lua)
plugin has support for Ruby LSP.

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

For LazyVim, you can add the ruby-lsp by creating a file in your plugins folder (`~/.config/nvim/plugins/ruby_lsp.lua`) and adding the following:

```lua
-- ~/.config/nvim/plugins/ruby_lsp.lua

return {
  {
    "neovim/nvim-lspconfig",
    ---@class PluginLspOpts
    opts = {
      ---@type lspconfig.options
      servers = {
        -- disable solargraph from auto running when you open ruby files
        solargraph = {
          autostart = false
        },
        -- ruby_lsp will be automatically installed with mason and loaded with lspconfig
        ruby_ls = {},
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

[https://plugins.jetbrains.com/plugin/24413-ruby-lsp](Ruby LSP plugin)
