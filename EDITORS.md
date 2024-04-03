# Editors

This file contains community driven instructions on how to set up the Ruby LSP in editors other than VS Code. For VS
Code, use the official [Ruby LSP extension](https://marketplace.visualstudio.com/items?itemName=Shopify.ruby-lsp).

<!-- When adding a new editor to the list, either link directly to a website containing the instructions or link to a
new H2 header in this file containing the instructions. -->

- [Emacs LSP Mode](https://emacs-lsp.github.io/lsp-mode/page/lsp-ruby-lsp/)
- [Emacs Eglot](#Emacs-Eglot)
- [Neovim LSP](#Neovim-LSP)
- [Sublime Text LSP](#sublime-text-lsp)

## Emacs Eglot

[Eglot](https://github.com/joaotavora/eglot) runs solargraph server by default. To set it up with ruby-lsp you need to
put that in your init file:
```el
(with-eval-after-load 'eglot
 (add-to-list 'eglot-server-programs '((ruby-mode ruby-ts-mode) "ruby-lsp")))
 ```

When you run `eglot` command it will run `ruby-lsp` process for you.

## Neovim

## nvim-lspconfig

The [nvim-lspconfig](https://github.com/neovim/nvim-lspconfig/blob/master/lua/lspconfig/server_configurations/ruby_ls.lua)
plugin has support for Ruby LSP.

## Mason

You can use [mason.nvim](https://github.com/williamboman/mason.nvim),
along with [mason-lspconfig.nvim](https://github.com/williamboman/mason-lspconfig.nvim):

```lua
local capabilities = vim.lsp.protocol.make_client_capabilities()
local mason_lspconfig = require("mason-lspconfig")
local servers = {
  ruby_ls = {},
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

## Neovim Limitations

Ruby LSP only supports pull diagnostics, and neovim versions prior to v0.10.0-dev-695+g58f948614 only support [publishDiagnostics](https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/#textDocument_publishDiagnostics).
Additional setup is required to enable diagnostics from Ruby LSP to appear in neovim.

```lua
-- textDocument/diagnostic support until 0.10.0 is released
_timers = {}
local function setup_diagnostics(client, buffer)
  if require("vim.lsp.diagnostic")._enable then
    return
  end

  local diagnostic_handler = function()
    local params = vim.lsp.util.make_text_document_params(buffer)
    client.request("textDocument/diagnostic", { textDocument = params }, function(err, result)
      if err then
        local err_msg = string.format("diagnostics error - %s", vim.inspect(err))
        vim.lsp.log.error(err_msg)
      end
      local diagnostic_items = {}
      if result then
        diagnostic_items = result.items
      end
      vim.lsp.diagnostic.on_publish_diagnostics(
        nil,
        vim.tbl_extend("keep", params, { diagnostics = diagnostic_items }),
        { client_id = client.id }
      )
    end)
  end

  diagnostic_handler() -- to request diagnostics on buffer when first attaching

  vim.api.nvim_buf_attach(buffer, false, {
    on_lines = function()
      if _timers[buffer] then
        vim.fn.timer_stop(_timers[buffer])
      end
      _timers[buffer] = vim.fn.timer_start(200, diagnostic_handler)
    end,
    on_detach = function()
      if _timers[buffer] then
        vim.fn.timer_stop(_timers[buffer])
      end
    end,
  })
end

-- adds ShowRubyDeps command to show dependencies in the quickfix list.
-- add the `all` argument to show indirect dependencies as well
local function add_ruby_deps_command(client, bufnr)
    vim.api.nvim_buf_create_user_command(bufnr, "ShowRubyDeps",
                                          function(opts)

        local params = vim.lsp.util.make_text_document_params()

        local showAll = opts.args == "all"

        client.request("rubyLsp/workspace/dependencies", params,
                        function(error, result)
            if error then
                print("Error showing deps: " .. error)
                return
            end

            local qf_list = {}
            for _, item in ipairs(result) do
                if showAll or item.dependency then
                    table.insert(qf_list, {
                        text = string.format("%s (%s) - %s",
                                              item.name,
                                              item.version,
                                              item.dependency),

                        filename = item.path
                    })
                end
            end

            vim.fn.setqflist(qf_list)
            vim.cmd('copen')
        end, bufnr)
    end, {nargs = "?", complete = function()
        return {"all"}
    end})
end


require("lspconfig").ruby_ls.setup({
  on_attach = function(client, buffer)
    setup_diagnostics(client, buffer)
    add_ruby_deps_command(client, buffer)
  end,
})
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
