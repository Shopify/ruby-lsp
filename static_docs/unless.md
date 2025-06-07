# Unless

The `unless` keyword in Ruby is used as a conditional statement that executes code when a condition is `false`. It's effectively the opposite of an `if` statement and is often used to make negative conditions more readable.

```ruby
def process_order(order)
  # Using unless to handle invalid cases
  unless order.valid?
    puts "Cannot process invalid order"
    return
  end
  
  # Process the valid order...
  order.process
end
```

## Guard clauses

`unless` is commonly used in guard clauses at the beginning of methods to handle invalid cases early:

```ruby
def send_notification(user)
  unless user.subscribed?
    return "User must be subscribed to receive notifications"
  end
  
  # Send the notification...
  NotificationService.deliver(user)
end
```

## Single line usage

For simple conditions, `unless` can be used as a statement modifier at the end of a line:

```ruby
def display_status(record)
  record.display_warning unless record.active?
  # More status handling...
end
```

## Best practices

1. Avoid using `else` with `unless` as it makes the logic harder to follow:

```ruby
# bad
unless success?
  puts "failure"
else
  puts "success"
end

# good
if success?
  puts "success"
else
  puts "failure"
end
```

2. Avoid complex conditions with `unless`. Use `if` with positive conditions instead:

```ruby
# bad
unless user.nil? || user.subscribed?
  notify_inactive_user(user)
end

# good
if user.present? && !user.subscribed?
  notify_inactive_user(user)
end
```

3. Don't use `unless` with multiple conditions joined by `&&`:

```ruby
# bad
unless user.active? && user.confirmed?
  handle_inactive_user
end

# good
if !user.active? || !user.confirmed?
  handle_inactive_user
end
``` 