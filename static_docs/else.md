# Else

The `else` keyword in Ruby is used to define code that should be executed when a condition in an `if` statement or `case` expression evaluates to `false`. It provides an alternative execution path when the main condition is not met.

## Basic Usage with If Statements

```ruby
if condition
  # Code executed when condition is true
else
  # Code executed when condition is false
end
```

For example:

```ruby
age = 15

if age >= 18
  puts "You can vote!"
else
  puts "You're too young to vote."
end
# => You're too young to vote.
```

## Multiple Conditions with Else

The `else` clause is always the final branch in a conditional statement. It catches all cases that weren't matched by previous conditions:

```ruby
score = 85

if score >= 90
  puts "A grade"
elsif score >= 80
  puts "B grade"
else
  puts "C grade or lower"
end
# => B grade
```

## Using Else with Case Statements

The `else` keyword can also be used with `case` statements as a default branch when no other conditions match:

```ruby
fruit = "orange"

case fruit
when "apple"
  puts "It's an apple"
when "banana"
  puts "It's a banana"
else
  puts "It's something else"
end
# => It's something else
```

## Else in Ternary Operations

Ruby also allows using a condensed if/else format called a ternary operator:

```ruby
age = 20
message = age >= 18 ? "Adult" : "Minor"
# => "Adult"
```

## Else with Unless

The `else` keyword can be used with `unless`, which is equivalent to `if !condition`:

```ruby
unless user.admin?
  puts "Access denied"
else
  puts "Welcome, admin!"
end
```

Remember that while `else` provides a way to handle alternative cases, too many conditional branches can make code harder to maintain. Consider refactoring complex conditional logic into separate methods or using polymorphism when appropriate. 