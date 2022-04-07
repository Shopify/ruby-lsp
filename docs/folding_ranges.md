# FoldingRanges

[Specification doc](https://microsoft.github.io/language-server-protocol/specifications/specification-current/#textDocument_foldingRange)

The folding ranges request provides informs the editor of the ranges where code can be folded.

Example:

~~~ruby
def say_hello # <-- folding range start
  puts "Hello"
end # <-- folding range end
~~~