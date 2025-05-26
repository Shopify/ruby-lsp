# Break

In Ruby, the `break` keyword is used to exit a loop or block prematurely. Unlike `next` which skips to the next iteration, `break` terminates the loop entirely and continues with the code after the loop.

```ruby
# Basic break usage in a loop
5.times do |i|
  break if i == 3

  puts i
end
# Output:
# 0
# 1
# 2
```

The `break` statement can be used with any of Ruby's iteration methods or loops.

```ruby
# Using break with different types of loops
array = [1, 2, 3, 4, 5]

# With each
array.each do |num|
  break if num > 3

  puts "Number: #{num}"
end
# Output:
# Number: 1
# Number: 2
# Number: 3

# With infinite loop
i = 0
loop do
  i += 1
  break if i >= 5

  puts "Count: #{i}"
end
```

## Break with a Value

When used inside a block, `break` can return a value that becomes the result of the method call.

```ruby
# Using break with a return value
result = [1, 2, 3, 4, 5].map do |num|
  break "Too large!" if num > 3

  num * 2
end
puts result # Output: "Too large!"

# Break in find method
number = (1..100).find do |n|
  break n if n > 50 && n.even?
end
puts number # Output: 52
```

## Break in Nested Loops

When using `break` in nested loops, it only exits the innermost loop unless explicitly used with a label (not commonly used in Ruby).

```ruby
# Break in nested iteration
result = (1..3).each do |i|
  puts "Outer loop: #{i}"

  (1..3).each do |j|
    break if j == 2

    puts "  Inner loop: #{j}"
  end
end
# Output:
# Outer loop: 1
#   Inner loop: 1
# Outer loop: 2
#   Inner loop: 1
# Outer loop: 3
#   Inner loop: 1

# Breaking from nested loops using a flag
found = false
(1..3).each do |i|
  (1..3).each do |j|
    if i * j == 4
      found = true
      break
    end
  end
  break if found
end
```

The `break` keyword is essential for controlling loop execution and implementing early exit conditions. It's particularly useful when you've found what you're looking for and don't need to continue iterating. 