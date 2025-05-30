# For

In Ruby, the `for` keyword creates a loop that iterates over a collection. While functional, Rubyists typically prefer using iterators like `each` for better readability and block scoping.

```ruby
# Basic for loop with a range
for i in 1..3
  puts i
end
# Output:
# 1
# 2
# 3
```

The `for` loop can iterate over any object that responds to `each`, including arrays and hashes.

```ruby
# Iterating over an array
fruits = ["apple", "banana", "orange"]

for fruit in fruits
  puts "I like #{fruit}"
end
# Output:
# I like apple
# I like banana
# I like orange

# Iterating over a hash
scores = { alice: 95, bob: 87 }

for name, score in scores
  puts "#{name} scored #{score}"
end
# Output:
# alice scored 95
# bob scored 87
```

## Variable Scope

Unlike block-based iterators, variables defined in a `for` loop remain accessible after the loop ends.

```ruby
# Variable remains in scope
for value in [1, 2, 3]
  doubled = value * 2
end

puts doubled # Output: 6 (last value)

# Comparison with each (creates new scope)
[1, 2, 3].each do |value|
  doubled = value * 2
end

# puts doubled # Would raise NameError
```

## Breaking and Next

The `for` loop supports control flow keywords like `break` and `next`.

```ruby
# Using break to exit early
for number in 1..5
  break if number > 3
  puts number
end
# Output:
# 1
# 2
# 3

# Using next to skip iterations
for number in 1..5
  next if number.even?
  puts number
end
# Output:
# 1
# 3
# 5
```

While Ruby provides the `for` loop for compatibility and familiarity, the preferred Ruby way is to use iterators with blocks:

```ruby
# Preferred Ruby style using each
(1..3).each { |i| puts i }

# For more complex iterations
(1..3).each do |i|
  puts i
end
``` 