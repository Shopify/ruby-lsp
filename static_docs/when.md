# When

The `when` keyword in Ruby is primarily used within `case` statements to define different conditions or patterns to match against. It's similar to `if/elsif` chains but often provides more readable and maintainable code when dealing with multiple conditions.

```ruby
grade = "A"

case grade
when "A"
  puts "Excellent!"
when "B"
  puts "Good job!"
when "C"
  puts "Fair"
else
  puts "Keep trying!"
end
# Prints: Excellent!
```

## Pattern matching

The `when` clause can match against multiple values using comma-separated expressions:

```ruby
day = "Saturday"

case day
when "Saturday", "Sunday"
  puts "It's the weekend!"
when "Monday"
  puts "Back to work!"
else
  puts "It's a regular weekday"
end
# Prints: It's the weekend!
```

## Range matching

`when` can match against ranges:

```ruby
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
# Prints: B grade
```

## Class/type matching

`when` can match against classes to check object types:

```ruby
data = [1, 2, 3]

case data
when String
  puts "Processing string: #{data}"
when Array
  puts "Processing array with #{data.length} elements"
when Hash
  puts "Processing hash with #{data.keys.length} keys"
else
  puts "Unknown data type"
end
# Prints: Processing array with 3 elements
```

## Pattern matching with 'in'

Ruby also supports advanced pattern matching with `in` patterns:

```ruby
response = { status: 200, body: { name: "Ruby" } }

case response
when { status: 200, body: { name: String => name } }
  puts "Success! Name: #{name}"
when { status: 404 }
  puts "Not found"
when { status: 500..599 }
  puts "Server error"
end
# Prints: Success! Name: Ruby
```

## Best practices

1. Use `when` with `case` when dealing with multiple conditions based on a single value:

```ruby
# Good - clear and concise with case/when
case status
when :pending
  process_pending
when :approved
  process_approved
when :rejected
  process_rejected
end

# Less clear with if/elsif chains
if status == :pending
  process_pending
elsif status == :approved
  process_approved
elsif status == :rejected
  process_rejected
end
```

2. Take advantage of pattern matching for complex conditions:

```ruby
# Good - using pattern matching capabilities
case user
when Admin
  handle_admin_access
when Moderator, Editor
  handle_moderator_access
when BasicUser
  handle_basic_access
end
```

3. Use comma-separated values instead of multiple `when` clauses for the same outcome:

```ruby
# Good - concise and clear
case day
when "Saturday", "Sunday"
  weekend_schedule
else
  weekday_schedule
end

# Less concise
case day
when "Saturday"
  weekend_schedule
when "Sunday"
  weekend_schedule
else
  weekday_schedule
end
``` 