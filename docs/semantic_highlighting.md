# SemanticHighlighting

[Specification doc](https://microsoft.github.io/language-server-protocol/specifications/specification-current/#textDocument_semanticTokens)

Highlights code consistently based on Ruby's understanding of the syntax.

Example:

~~~ruby
local_variable = 1
local_variable # --> Highlighted properly as a local variable despite the ambiguity with method calls
~~~