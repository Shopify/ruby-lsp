# Version Managers

This document contains information and tips to help Ruby LSP's VS Code extension work with your Ruby version manager.

## asdf

Ensure you on the latest release of asdf: https://asdf-vm.com/manage/commands.html.
If `asdf` was installed through Homebrew then you may need to first run `brew upgrade asdf`.

If you use `asdf` and the VS Code extension fails to activate the environment (as described in [this issue](https://github.com/Shopify/ruby-lsp/issues/1985)), you may resolve it by updating `asdf` to the latest version with `asdf update`, and then restart VS Code.

## Chruby

Ensure you are on the latest release of chruby.

If you use `chruby` but don't have a `.ruby-version` file in the project root, you can add `.ruby-version` to its parent folder as a fallback.

For example, if `/projects/my_project` doesn't have `.ruby-version`, `chruby` would read `/projects/.ruby-version` instead.

## Mise

Ensure Mise is up-to-date: https://mise.jdx.dev/faq.html#mise-is-failing-or-not-working-right

## RVM

Ensure RVM is up-to-date: https://rvm.io/rvm/upgrading

## Custom activation

If you're using a different version manager that's not supported by this extension or if you're manually inserting the Ruby
executable into the PATH, you will probably need to define custom activation so that the extension can find the correct
Ruby.

For these cases, set `rubyLsp.rubyVersionManager.identifier` to `"custom"` and then set `rubyLsp.customRubyCommand` to a
shell command that will activate the right Ruby version or add the Ruby `bin` folder to the `PATH`. Some examples:

```jsonc
{
  // Don't forget to set the manager to custom when using this option
  "rubyLsp.rubyVersionManager": {
    "identifier": "custom",
  },

  // Using a different version manager than the ones included by default
  "rubyLsp.customRubyCommand": "my_custom_version_manager activate",

  // Adding a custom Ruby bin folder to the PATH
  "rubyLsp.customRubyCommand": "PATH=/path/to/ruby/bin:$PATH",
}
```
