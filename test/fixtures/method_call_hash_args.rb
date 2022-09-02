foo("positional", bar: "one", baz: "two")

foo(
  "positional",
  bar: "three",
  baz: "four",
)

foo("positional", bar: "five",
  baz: "six")

puts bar: "one"

foo "positional", bar: "one", baz: "two"
