# DocumentSymbol

[Specification doc](https://microsoft.github.io/language-server-protocol/specifications/specification-current/#textDocument_documentSymbol)

Populates the information about important symbols found in a file to allow for navigation.

Example:

~~~ruby
module MyModule # --> Symbol with kind: :module
 class MyClass # --> Symbol with kind: :class
  attr_reader :my_var # --> Symbol with kind: :field

  def initialize # --> Symbol with kind: :constructor
    @my_var = 1 # --> Symbol with kind: :variable
  end
 end
end
~~~