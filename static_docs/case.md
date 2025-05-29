# Case Statement

In Ruby, the `case` statement provides a clean way to express conditional logic when you need to compare a value against multiple conditions. It's similar to if/else chains but often more readable and concise.

```ruby
# Basic case statement comparing a value against multiple conditions
grade = "A"

case grade
when "A"
  puts "Excellent!"
when "B"
  puts "Good job!"
when "C"
  puts "Fair"
else
  puts "Need improvement"
end
```

The `case` statement can also work with ranges, multiple values, and even custom matching using the `===` operator.

```ruby
# Case statement with ranges and multiple conditions
score = 85

case score
when 90..100
  puts "A grade"
when 80..89
  puts "B grade"
when 70..79
  puts "C grade"
else
  puts "Need improvement"
end

# Case with multiple values in a single when clause
day = "Saturday"

case day
when "Saturday", "Sunday"
  puts "Weekend!"
else
  puts "Weekday"
end
```

## Pattern Matching (Ruby 2.7+)

Starting from Ruby 2.7, `case` statements support pattern matching, which provides powerful ways to match and destructure data.

```ruby
# Pattern matching with arrays
data = [1, 2, 3]

case data
when [1, 2, 3]
  puts "Exact match!"
when [1, *rest]
  puts "Starts with 1, followed by #{rest}"
when Array
  puts "Any array"
else
  puts "Not an array"
end

# Pattern matching with hashes (Ruby 3.0+)
user = { name: "Alice", age: 30 }

case user
in { name: "Alice", age: }
  puts "Alice is #{age} years old"
in { name:, age: 20.. }
  puts "#{name} is at least 20"
else
  puts "No match"
end
```

## Case without an argument

Ruby also allows `case` statements without an explicit argument, which acts like a series of if/elsif conditions.

```ruby
# Case statement without an argument
case
when Time.now.saturday?
  puts "It's Saturday!"
when Time.now.sunday?
  puts "It's Sunday!"
else
  puts "It's a weekday"
end
```

The case statement is particularly useful when you have multiple conditions to check against a single value, or when you want to use pattern matching to destructure complex data structures.