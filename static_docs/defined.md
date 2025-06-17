# Defined?

In Ruby, the `defined?` keyword is a special operator that checks whether a given expression is defined and returns a description of that expression, or `nil` if the expression is not defined.

```ruby
# Basic defined? usage
x = 42
puts defined?(x)      # Output: local-variable
puts defined?(y)      # Output: nil
puts defined?(puts)   # Output: method
```

The `defined?` operator can check various types of expressions and returns different description strings based on the type.

```ruby
# Checking different types
class Example
  CONSTANT = "Hello"

  def check_definitions
    @instance_var = "!"

    puts defined?(CONSTANT) # Output: constant
    puts defined?(@instance_var) # Output: instance-variable
    puts defined?(yield) # Output: yield (if block given)
    puts defined?(super) # Output: super (if method has super)
  end
end

example = Example.new
puts defined?(Example)   # Output: constant
puts defined?(String)    # Output: constant
puts defined?("string")  # Output: expression
```

## Common Use Cases

The `defined?` operator is often used for safe navigation and checking existence before execution.

```ruby
def safe_operation(value)
  return "No block given" unless defined?(yield)

  if defined?(value.length)
    "Length is #{value.length}"
  else
    "Cannot determine length"
  end
end

puts safe_operation([1, 2, 3]) { |x| x * 2 }  # Output: Length is 3
puts safe_operation(42) { |x| x * 2 }         # Output: Cannot determine length
puts safe_operation([1, 2, 3])                # Output: No block given
```

## Method and Block Checking

`defined?` is particularly useful for checking method existence and block presence.

```ruby
class SafeCaller
  def execute
    if defined?(before_execute)
      before_execute
    end

    puts "Executing main logic"

    if defined?(after_execute)
      after_execute
    end
  end

  def after_execute
    puts "After execution"
  end
end

caller = SafeCaller.new
caller.execute
# Output:
# Executing main logic
# After execution

# Block checking
def process_with_block
  if defined?(yield)
    "Block given: #{yield}"
  else
    "No block given"
  end
end

puts process_with_block { "Hello!" }  # Output: Block given: Hello!
puts process_with_block               # Output: No block given
```

The `defined?` operator is a powerful tool for writing defensive code and handling optional features or dependencies in Ruby programs. 