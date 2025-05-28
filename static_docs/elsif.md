# Elsif

The `elsif` keyword in Ruby allows you to check multiple conditions in sequence. It's used to add additional conditions to an `if` statement when the previous condition is false, providing a way to handle multiple distinct cases.

## Basic Usage

```ruby
if condition1
  # Code executed when condition1 is true
elsif condition2
  # Code executed when condition1 is false AND condition2 is true
else
  # Code executed when all conditions are false
end
```

For example:

```ruby
temperature = 75

if temperature > 90
  puts "It's very hot!"
elsif temperature > 70
  puts "It's warm."
elsif temperature > 50
  puts "It's cool."
else
  puts "It's cold!"
end
# => It's warm.
```

## Multiple Elsif Branches

You can chain multiple `elsif` statements to handle various conditions:

```ruby
grade = 85

if grade >= 90
  puts "A grade"
elsif grade >= 80
  puts "B grade"
elsif grade >= 70
  puts "C grade"
elsif grade >= 60
  puts "D grade"
else
  puts "F grade"
end
# => B grade
```

## Elsif vs Case Statements

While `elsif` is useful for checking different conditions, when you're comparing the same value against multiple options, a `case` statement might be more readable:

```ruby
# Using elsif
day = "Monday"

if day == "Saturday" || day == "Sunday"
  puts "Weekend!"
elsif day == "Friday"
  puts "TGIF!"
else
  puts "Weekday"
end

# Equivalent case statement (often clearer for this type of comparison)
case day
when "Saturday", "Sunday"
  puts "Weekend!"
when "Friday"
  puts "TGIF!"
else
  puts "Weekday"
end
```

## Complex Conditions

`elsif` conditions can include complex boolean expressions:

```ruby
user_age = 25
has_id = true
is_member = false

if user_age < 18
  puts "Too young"
elsif user_age >= 18 && has_id && is_member
  puts "Welcome to the VIP section"
elsif user_age >= 18 && has_id
  puts "Welcome to the regular section"
else
  puts "Please provide ID"
end
# => Welcome to the regular section
```

## Best Practices

1. Consider using a `case` statement when comparing a single value against multiple options
2. Keep conditions simple and readable
3. Consider extracting complex conditions into well-named methods
4. Don't overuse `elsif` - if you have too many conditions, consider refactoring into a more object-oriented approach

```ruby
# Instead of many elsif statements
def process_status(status)
  if status == "pending"
    handle_pending
  elsif status == "processing"
    handle_processing
  elsif status == "completed"
    handle_completed
  elsif status == "failed"
    handle_failed
  end
end

# Consider using a hash or object-oriented approach
STATUS_HANDLERS = {
  "pending" => :handle_pending,
  "processing" => :handle_processing,
  "completed" => :handle_completed,
  "failed" => :handle_failed
}

def process_status(status)
  send(STATUS_HANDLERS[status])
end
``` 