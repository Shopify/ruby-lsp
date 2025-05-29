# Return

In Ruby, `return` is used to explicitly return a value from a method or block. While Ruby automatically returns the value of the last evaluated expression, `return` allows you to exit the method early and specify the return value.

```ruby
def greet(name)
  return "Hello, #{name}!"
end

puts greet("Ruby") # => "Hello, Ruby!"
```

When no value is provided to `return`, it returns `nil`:

```ruby
def early_exit
  return if condition?
  # Code here won't execute if condition? is true
  perform_task
end
```

## Multiple values

Ruby allows returning multiple values, which are automatically converted into an array:

```ruby
def calculate_stats(numbers)
  sum = numbers.sum
  average = sum / numbers.length.to_f
  return sum, average
end

total, mean = calculate_stats([1, 2, 3, 4])
puts total  # => 10
puts mean   # => 2.5
```

## Early returns

Using `return` for early exits can help make code more readable by reducing nesting:

```ruby
# Without early return
def process_user(user)
  if user.active?
    if user.admin?
      perform_admin_task
    else
      perform_regular_task
    end
  else
    puts "Inactive user"
  end
end

# With early return
def process_user(user)
  return puts "Inactive user" unless user.active?
  return perform_admin_task if user.admin?
  perform_regular_task
end
```

## Return in blocks

When used inside a block, `return` will exit from the method that yielded to the block:

```ruby
def process_items
  [1, 2, 3].each do |item|
    return item if item > 1
    puts "Processing #{item}"
  end
  puts "Done processing"
end

result = process_items
# Prints "Processing 1"
puts result # => 2
```

## Return in procs vs lambdas

The behavior of `return` differs between procs and lambdas:

```ruby
# In a proc, return exits the enclosing method
def proc_return
  proc = Proc.new { return "From proc" }
  proc.call
  "From method" # Never reached
end

puts proc_return # => "From proc"

# In a lambda, return only exits the lambda itself
def lambda_return
  lambda = -> { return "From lambda" }
  lambda.call
  "From method" # This is reached
end

puts lambda_return # => "From method"
```

When using `return`, consider:
- Whether an implicit return would be clearer
- If early returns improve code readability
- The context (proc vs lambda) when using `return` in blocks
- Using multiple returns judiciously 