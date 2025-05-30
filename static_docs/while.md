# While

The `while` keyword in Ruby creates a loop that executes a block of code as long as a given condition is true. The condition is checked before each iteration.

```ruby
counter = 0

while counter < 3
  puts counter
  counter += 1
end
# Prints:
# 0
# 1
# 2
```

## Basic usage with break

The `break` keyword can be used to exit a `while` loop prematurely:

```ruby
number = 1

while true # infinite loop
  puts number
  break if number >= 3
  number += 1
end
# Prints:
# 1
# 2
# 3
```

## Using next to skip iterations

The `next` keyword can be used to skip to the next iteration:

```ruby
counter = 0

while counter < 5
  counter += 1
  next if counter.even? # Skip even numbers
  puts counter
end
# Prints:
# 1
# 3
# 5
```

## While with begin (do-while equivalent)

Ruby doesn't have a direct do-while loop, but you can achieve similar behavior using `begin...end while`:

```ruby
count = 5

begin
  puts count
  count -= 1
end while count > 0
# Prints:
# 5
# 4
# 3
# 2
# 1
```

## Best practices

1. Use `while` when you need to loop based on a condition rather than a specific number of iterations:

```ruby
# Good - clear condition-based looping
input = gets.chomp
while input != "quit"
  process_input(input)
  input = gets.chomp
end

# Less appropriate for condition-based looping
loop do
  input = gets.chomp
  break if input == "quit"
  process_input(input)
end
```

2. Consider using `until` for negative conditions instead of `while !condition`:

```ruby
# Good - using until for negative conditions
until queue.empty?
  process_item(queue.pop)
end

# Less readable
while !queue.empty?
  process_item(queue.pop)
end
```

3. Use `while true` sparingly and ensure there's a clear exit condition:

```ruby
# Good - clear exit condition with break
while true
  command = get_command
  break if command == "exit"
  execute_command(command)
end

# Better - using a more explicit condition
command = get_command
while command != "exit"
  execute_command(command)
  command = get_command
end
``` 