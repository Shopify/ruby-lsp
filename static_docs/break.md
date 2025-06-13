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
array = [1, 2, 3, 4, 5]

# Break in each iteration
array.each do |num|
  break if num > 3

  puts "Number: #{num}"
end
# Output:
# Number: 1
# Number: 2
# Number: 3

# Break in an infinite loop
count = 0
loop do
  count += 1
  break if count >= 3

  puts "Count: #{count}"
end
# Output:
# Count: 1
# Count: 2
```

## Break with a Value

When used inside a block, `break` can return a value that becomes the result of the method call.

```ruby
# Break with a return value in map
result = [1, 2, 3, 4, 5].map do |num|
  break "Too large!" if num > 3

  num * 2
end
puts result # Output: "Too large!"

# Break with a value in find
number = (1..10).find do |n|
  break n if n > 5 && n.even?
end
puts number # Output: 6
```

## Break in Nested Loops

When using `break` in nested loops, it only exits the innermost loop. To break from nested loops, you typically need to use a flag or return.

```ruby
# Break in nested iteration
(1..3).each do |i|
  puts "Outer: #{i}"

  (1..3).each do |j|
    break if j == 2

    puts "  Inner: #{j}"
  end
end
# Output:
# Outer: 1
#   Inner: 1
# Outer: 2
#   Inner: 1
# Outer: 3
#   Inner: 1

# Breaking from nested loops with a flag
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