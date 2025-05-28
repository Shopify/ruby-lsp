# Do

In Ruby, the `do` keyword is used to create blocks of code, typically in conjunction with iterators, loops, or method definitions. It's often interchangeable with curly braces `{}`, but with different precedence rules and conventional usage patterns.

```ruby
# Basic do...end block with an iterator
[1, 2, 3].each do |number|
  puts number
end
# Output:
# 1
# 2
# 3
```

## Do vs Curly Braces

While `do...end` and `{}` can often be used interchangeably, there are conventional and practical differences.

```ruby
# Single-line blocks typically use curly braces
[1, 2, 3].map { |n| n * 2 }

# Multi-line blocks typically use do...end
[1, 2, 3].map do |n|
  result = n * 2
  result + 1
end

# Precedence differences
puts [1, 2, 3].map { |n| n * 2 }  # Works as expected
puts [1, 2, 3].map do |n| n * 2 end  # May not work as expected due to precedence
```

## Do with While and Until

The `do` keyword is also used with `while` and `until` loops to create do-while style loops where the condition is checked after the first iteration.

```ruby
# Basic while loop
i = 0
while i < 3 do  # 'do' is optional here
  puts i
  i += 1
end

# do...while equivalent (condition checked after)
i = 0
begin
  puts i
  i += 1
end while i < 3

# until with do
j = 0
until j > 3 do  # 'do' is optional here
  puts j
  j += 1
end
```

## Do in Method Definitions

When defining methods that take blocks, the block can be passed using either `do...end` or curly braces.

```ruby
# Method that takes a block
def repeat_twice
  2.times do
    yield if block_given?
  end
end

# Using the method with do...end
repeat_twice do
  puts "Hello!"
end
# Output:
# Hello!
# Hello!

# Using the method with curly braces
repeat_twice { puts "Hi!" }
# Output:
# Hi!
# Hi!
```

The `do` keyword is fundamental to Ruby's block syntax and is particularly useful for creating readable, multi-line blocks of code. The choice between `do...end` and `{}` is often a matter of convention and readability, with `do...end` being preferred for multi-line blocks. 