# Rescue

In Ruby, `rescue` is used to handle exceptions that occur during program execution. It allows you to catch and handle errors gracefully, preventing your program from crashing.

```ruby
# Basic rescue usage
begin
  # Code that might raise an exception
  result = 10 / 0
rescue
  puts "An error occurred!"
end
```

You can specify which type of exception to rescue, and capture the exception object for inspection:

```ruby
begin
  # Attempting to divide by zero raises a ZeroDivisionError
  result = 10 / 0
rescue ZeroDivisionError => e
  puts "Cannot divide by zero: #{e.message}"
end
```

Multiple rescue clauses can be used to handle different types of exceptions:

```ruby
begin
  # Code that might raise different types of exceptions
  JSON.parse(invalid_json)
rescue JSON::ParserError => e
  puts "Invalid JSON format: #{e.message}"
rescue StandardError => e
  puts "Some other error occurred: #{e.message}"
end
```

## Inline rescue

Ruby also supports inline rescue clauses for simple error handling:

```ruby
# If the division fails, return nil instead
result = 10 / params[:divisor].to_i rescue nil

# This is equivalent to:
result = begin
  10 / params[:divisor].to_i
rescue
  nil
end
```

## Ensure and else clauses

The `rescue` keyword can be used with `ensure` and `else` clauses:

```ruby
begin
  # Attempt some operation
  file = File.open("example.txt")
  content = file.read
rescue Errno::ENOENT => e
  puts "Could not find the file: #{e.message}"
else
  # This block only executes if no exception was raised
  puts "Successfully read #{content.length} bytes"
ensure
  # This block always executes, whether an exception occurred or not
  file&.close
end
```

## Method-level rescue

You can also use `rescue` at the method level without an explicit `begin` block:

```ruby
def process_file(path)
  File.read(path)
rescue Errno::ENOENT
  puts "File not found"
rescue Errno::EACCES
  puts "Permission denied"
end
```

When rescuing exceptions, it's important to:
- Only rescue specific exceptions you can handle
- Avoid rescuing `Exception` as it captures all exceptions, including system ones
- Use `ensure` for cleanup code that must always run
- Keep the rescue block focused on error handling logic 