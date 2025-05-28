# Begin

In Ruby, the `begin` keyword serves two main purposes: starting an exception handling block and ensuring code executes in a specific order. It's commonly used with `rescue`, `else`, and `ensure` clauses.

## Exception Handling

The most common use of `begin` is for exception handling:

```ruby
begin
  # Code that might raise an exception
  result = dangerous_operation
rescue StandardError => e
  # Handle the error
  puts "Error occurred: #{e.message}"
else
  # Runs only if no exception was raised
  puts "Operation succeeded with result: #{result}"
ensure
  # Always runs, whether an exception occurred or not
  cleanup_resources
end
```

You can rescue multiple exception types and handle them differently:

```ruby
begin
  response = HTTP.get("https://api.example.com/data")
  data = JSON.parse(response.body)
rescue HTTP::ConnectionError => e
  puts "Network error: #{e.message}"
rescue JSON::ParserError => e
  puts "Invalid JSON response: #{e.message}"
rescue StandardError => e
  puts "Unexpected error: #{e.message}"
end
```

## Ensuring Code Execution Order

The `begin` keyword can also ensure that a block of code executes in order, particularly useful in method definitions:

```ruby
def process_file(path)
  file = File.open(path)
  begin
    content = file.read
    process_content(content)
  ensure
    file.close
  end
end
```

## Inline Exception Handling

Ruby allows a more concise syntax for simple exception handling using `begin` inline:

```ruby
# Single-line rescue
result = begin
  potentially_dangerous_operation
rescue StandardError
  default_value
end

# Equivalent to:
result = potentially_dangerous_operation rescue default_value
```

## Begin with Retry

The `begin` block can be used with `retry` to attempt an operation multiple times:

```ruby
attempts = 0
begin
  response = HTTP.get("https://api.example.com/data")
rescue HTTP::ConnectionError => e
  attempts += 1
  if attempts < 3
    puts "Retrying... (attempt #{attempts + 1})"
    retry
  else
    puts "Failed after #{attempts} attempts"
    raise
  end
end
```

## Implicit Begin Blocks

Ruby provides implicit `begin` blocks in certain contexts, such as method definitions and class bodies:

```ruby
# Explicit begin block
def save_record
  begin
    perform_save
  rescue ActiveRecord::RecordInvalid => e
    handle_validation_error(e)
  end
end

# Equivalent implicit begin block
def save_record
  perform_save
rescue ActiveRecord::RecordInvalid => e
  handle_validation_error(e)
end
```

## Best Practices

1. Only rescue specific exceptions you can handle:
```ruby
begin
  # Some code
rescue SpecificError => e
  # Handle specific error
end
```

2. Use implicit begin blocks when possible for cleaner code:
```ruby
def process_data
  # Implicit begin
  parse_data
  save_result
rescue ParseError => e
  log_error(e)
end
```

3. Always include an `ensure` block when resources need to be cleaned up:
```ruby
def process_file(path)
  file = File.open(path)
  begin
    process_content(file.read)
  ensure
    file.close
  end
end
```

4. Use `else` clause for code that should only run if no exceptions occur:
```ruby
begin
  result = perform_operation
rescue OperationError => e
  handle_error(e)
else
  # Only runs if no exception occurred
  log_success(result)
ensure
  cleanup
end
``` 