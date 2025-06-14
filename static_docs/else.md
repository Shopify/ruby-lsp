# Else

In Ruby, the `else` keyword is used to define an alternative execution path in conditional statements. It works with `if`, `unless`, `case`, and `begin/rescue` blocks to handle cases when the primary conditions are not met.

```ruby
# Basic else usage with if
status = "error"

if status == "success"
  puts "Operation completed"
else
  puts "Operation failed"
end
# Output:
# Operation failed
```

The `else` clause can be used with various conditional structures in Ruby.

```ruby
# With if (positive condition)
temperature = 25

if temperature >= 20
  puts "It's warm"
else
  puts "It's cool"
end
# Output:
# It's warm

# With case statement
grade = "B"

case grade
when "A"
  puts "Excellent!"
when "B"
  puts "Good job!"
else
  puts "Keep working hard!"
end
# Output:
# Good job!
```

## Error Handling

The `else` keyword is commonly used with `begin/rescue` blocks for error handling.

```ruby
begin
  result = 10 / 0
rescue ZeroDivisionError
  puts "Cannot divide by zero"
else
  # Executes only if no error was raised
  puts "Result: #{result}"
ensure
  puts "Calculation attempted"
end
# Output:
# Cannot divide by zero
# Calculation attempted
```

## Ternary Operator Alternative

For simple conditions, Ruby provides a ternary operator as a concise alternative to `if/else`.

```ruby
def check_temperature(temp)
  temp >= 25 ? "It's hot" : "It's cool"
end

puts check_temperature(30) # Output: It's hot
puts check_temperature(20) # Output: It's cool

# Compared to if/else
def check_temperature_verbose(temp)
  if temp >= 25
    "It's hot"
  else
    "It's cool"
  end
end
```

## Method Return Values

The `else` clause affects the return value in conditional expressions.

```ruby
def process_number(num)
  if num.even?
    "Even number: #{num}"
  else
    "Odd number: #{num}"
  end
end

puts process_number(42)  # Output: Even number: 42
puts process_number(37)  # Output: Odd number: 37
```

The `else` keyword is fundamental to control flow in Ruby, providing clear paths for alternate execution when conditions are not met. 