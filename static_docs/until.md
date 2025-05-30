# Until

In Ruby, the `until` keyword creates a loop that executes code until a condition becomes `true`. It's effectively the opposite of a `while` loop and is often used when you want to continue an action while a condition is `false`.

```ruby
counter = 0

until counter >= 5
  puts counter
  counter += 1
end
# Prints:
# 0
# 1
# 2
# 3
# 4
```

The `until` loop first evaluates the condition. If the condition is `false`, it executes the code block. After each iteration, it checks the condition again. When the condition becomes `true`, the loop ends.

## Modifier form

Like many Ruby control structures, `until` can be used as a statement modifier at the end of a line:

```ruby
# Keep prompting for input until a valid response is received
response = gets.chomp
response = gets.chomp until response.downcase == "yes" || response.downcase == "no"
```

## Break and next

You can use `break` to exit an `until` loop early and `next` to skip to the next iteration:

```ruby
number = 0

until number > 10
  number += 1
  next if number.odd?  # Skip odd numbers
  puts number          # Print only even numbers
  break if number == 8 # Stop when we reach 8
end
# Prints:
# 2
# 4
# 6
# 8
```

## Begin/Until

Ruby also provides a `begin/until` construct that ensures the loop body is executed at least once before checking the condition:

```ruby
attempts = 0

begin
  attempts += 1
  result = perform_operation
end until result.success? || attempts >= 3

# The operation will be attempted at least once, and up to three times
# if it doesn't succeed
```

## Best practices

1. Use `until` when waiting for a condition to become `true`:

```ruby
# Good - clear that we're waiting for readiness
until server.ready?
  sleep 1
end

# Less clear intention
while !server.ready?
  sleep 1
end
```

2. Consider using `while` with positive conditions instead of `until` with negative ones:

```ruby
# Less clear with double negative
until !queue.empty?
  process_next_item
end

# Better - clearer intention
while queue.any?
  process_next_item
end
```

3. Use modifier form for simple, single-line operations:

```ruby
# Good - concise and clear
retry_operation until successful?

# Less concise for simple operations
until successful?
  retry_operation
end
``` 