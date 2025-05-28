# Next

In Ruby, the `next` keyword is used to skip to the next iteration of a loop. It's similar to `continue` in other programming languages and helps control the flow of iteration without breaking out of the loop entirely.

```ruby
# Basic next usage in a loop
5.times do |i|
  next if i == 2  # Skip when i is 2
  puts i
end
# Output:
# 0
# 1
# 3
# 4
```

The `next` statement can be used with any of Ruby's iteration methods or loops.

```ruby
# Using next with different types of loops
array = [1, 2, 3, 4, 5]

# With each
array.each do |num|
  next if num.even?  # Skip even numbers
  puts "Odd number: #{num}"
end
# Output:
# Odd number: 1
# Odd number: 3
# Odd number: 5

# With while loop
i = 0
while i < 5
  i += 1
  next if i == 3  # Skip when i is 3
  puts "Current number: #{i}"
end
```

## Next with a Value

When used inside a block that's expected to return values (like `map`), `next` can take an argument that serves as the value for the current iteration.

```ruby
# Using next with a value in map
result = [1, 2, 3, 4, 5].map do |num|
  next 0 if num.even?  # Replace even numbers with 0
  num * 2             # Double odd numbers
end
puts result.inspect
# Output: [2, 0, 6, 0, 10]

# Another example with select_map (Ruby 2.7+)
numbers = [1, 2, 3, 4, 5].map do |num|
  next nil if num < 3  # Replace numbers less than 3 with nil
  num ** 2            # Square numbers >= 3
end
puts numbers.compact.inspect  # Remove nil values
# Output: [9, 16, 25]
```

## Next in Nested Loops

When using `next` in nested loops, it only affects the innermost loop where it appears.

```ruby
# Next in nested iteration
(1..3).each do |i|
  puts "Outer loop: #{i}"
  
  (1..3).each do |j|
    next if i == j  # Skip when numbers match
    puts "  Inner loop: #{j}"
  end
end
# Output:
# Outer loop: 1
#   Inner loop: 2
#   Inner loop: 3
# Outer loop: 2
#   Inner loop: 1
#   Inner loop: 3
# Outer loop: 3
#   Inner loop: 1
#   Inner loop: 2
```

The `next` keyword is particularly useful when you want to skip certain iterations based on conditions without breaking the entire loop's execution. It helps make code more readable by avoiding deeply nested conditional blocks. 