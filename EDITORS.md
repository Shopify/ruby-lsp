# Editors

This file contains community driven instructions on how to set up the Ruby LSP in editors other than VS Code. For VS
Code, use the official [Ruby LSP extension](https://github.com/Shopify/vscode-ruby-lsp).

<!-- When adding a new editor to the list, either link directly to a website containing the instructions or link to a
new H2 header in this file containing the instructions. -->

- [Emacs LSP Mode](https://emacs-lsp.github.io/lsp-mode/page/lsp-ruby-lsp/)
- [neovim](#neovim-via-nvim-lspconfig) (via [nvim-lspconfig](https://github.com/neovim/nvim-lspconfig))

## Neovim (via [nvim-lspconfig](https://github.com/neovim/nvim-lspconfig))

- Install [nvim-lspconfig](https://github.com/neovim/nvim-lspconfig) via your favourite plugin manager (eg: [Packer](https://github.com/wbthomason/packer.nvim)).
- Enable nvim-lspconfig's ruby_ls configuration:
  ```lua
  require('lspconfig').ruby_ls.setup {
    init_options = {
      -- Add Ruby LSP configuration here, eg:
      -- formatter = 'auto'
    },
    -- Add your lspconfig configurations/overrides here, eg:
    on_attach = function(client, buffer)
      -- ...
    end,
  }
  ```
- To make inline diagnostics (`textDocument/diagnostics`) work you need to [add a custom handler](https://github.com/neovim/nvim-lspconfig/pull/2498).
