# Custom version managers

Below you can find user-contributed configurations for less common version managers.

## rtx

[rtx](https://github.com/jdxcode/rtx) is a Rust clone compatible with asdf. You can use it by adding the following
snippet to your user configuration JSON

```json
{
  "rubyLsp.rubyVersionManager": "custom",
  "rubyLsp.customRubyCommand": "eval \"$(rtx env -s zsh)\"", // Instructions for zsh, change for bash or fish
}
```
