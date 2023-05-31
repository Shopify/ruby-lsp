# Semantic highlighting

The Ruby LSP supports semantic highlighting. This feature informs editors about the right token types for each part of
the code to allow for rich and accurate highlighting. The strategy taken by the Ruby LSP is to only return tokens for
syntax that is ambiguous in Ruby (as opposed to all existing tokens) to optimize for performance.

An example of ambiguous syntax in Ruby are local variables and method calls. If you look at this line in isolation:
```ruby
foo
```
it is not possible to tell if `foo` is a local variable or a method call. It depends on whether `foo` was assigned to
something before or not. This is one scenario where semantic highlighting removes the ambiguity for themes, returning
the correct token type by statically analyzing the code.

To enhance a theme's Ruby syntax highlighting using the Ruby LSP, check the information below. You may also want to
check out the [Spinel theme](https://github.com/Shopify/vscode-shopify-ruby/blob/main/themes/dark_spinel.json) as an
example, which uses all of the Ruby LSP's semantic highlighting information.

## Token types

According to the LSP specification, language servers can either use token types and modifiers from the [default
list](https://microsoft.github.io/language-server-protocol/specification#semanticTokenTypes) or contribute new semantic
tokens of their own. Currently, the Ruby LSP does not contribute any new semantic tokens and only uses the ones
contained in the default list.

## Token list

| Syntax  | Type.Modifier | Note |
| ------------- | ------------- | ------------- |
| Sorbet annotation methods such as `let` or `cast`  | type | Not every annotation is handled |
| Method calls with any syntax  | method | |
| Constant references (including classes and modules)  | namespace | We don't yet differentiate between module and class references |
| Method definition  | method.declaration | |
| self  | variable.default_library | |
| Method, block and lambda arguments | parameter | |
| Class declaration | class.declaration | |
| Module declaration | class.declaration | |
