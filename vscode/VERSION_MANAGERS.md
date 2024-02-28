## Chruby

If you use `chruby` but don't have a `.ruby-version` file in the project root, you can add `.ruby-version` to its parent folder as a fallback.

For example, if `/projects/my_project` doesn't have `.ruby-version`, `chruby` would read `/projects/.ruby-version` instead.

## Custom activation

If you're using a different version manager that's not supported by this extension or if you're manually inserting the Ruby
executable into the PATH, you will probably need to define custom activation so that the extension can find the correct
Ruby.

For these cases, set `rubyLsp.rubyVersionManager` to `"custom"` and then set `rubyLsp.customRubyCommand` to a shell
command that will activate the right Ruby version or add the Ruby `bin` folder to the `PATH`. Some examples:

```jsonc
{
  // Don't forget to set the manager to custom when using this option
  "rubyLsp.rubyVersionManager": "custom",

  // Using a different version manager than the ones included by default
  "rubyLsp.customRubyCommand": "my_custom_version_manager activate",

  // Adding a custom Ruby bin folder to the PATH
  "rubyLsp.customRubyCommand": "PATH=/path/to/ruby/bin:$PATH",
}
```

### mise (formerly rtx)

[mise](https://github.com/jdx/mise) is a Rust clone compatible with asdf. You can use it by adding the following
snippet to your user configuration JSON

```json
{
  "rubyLsp.rubyVersionManager": "custom",
  "rubyLsp.customRubyCommand": "eval \"$(mise env -s zsh)\"" // Instructions for zsh, change for bash or fish
}
```
