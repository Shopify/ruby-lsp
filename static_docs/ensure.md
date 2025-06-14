# Ensure

In Ruby, the `ensure` keyword is used to define a block of code that will always execute, regardless of whether an exception was raised or not. It's commonly used for cleanup operations like closing files or network connections.

```ruby
# Basic ensure usage
file = File.open("example.txt")
begin
  content = file.read
rescue StandardError => e
  puts "Error reading file: #{e.message}"
ensure
  file.close # Always executes
end
```

The `ensure` clause can be used with or without `rescue` blocks, and it will execute even if there's a return statement in the main block.

```ruby
def process_data
  connection = Database.connect
  begin
    return connection.query("SELECT * FROM users")
  ensure
    connection.close # Executes even with the return statement
  end
end

# Without rescue clause
def write_log(message)
  file = File.open("log.txt", "a")
  begin
    file.puts(message)
  ensure
    file.close
  end
end
```

## Multiple Rescue Clauses

When using multiple `rescue` clauses, the `ensure` block always comes last and executes regardless of which `rescue` clause is triggered.

```ruby
def perform_operation
  begin
    # Main operation
    result = dangerous_operation
  rescue ArgumentError => e
    puts "Invalid arguments: #{e.message}"
  rescue StandardError => e
    puts "Other error: #{e.message}"
  ensure
    # Cleanup code always runs
    cleanup_resources
  end
end
```

## Implicit Begin Blocks

In methods and class definitions, you can use `ensure` without an explicit `begin` block.

```ruby
def process_file(path)
  file = File.open(path)
  file.read # If this raises an error, ensure still executes
ensure
  file&.close # Using safe navigation operator in case file is nil
end

class DataProcessor
  def initialize
    @connection = Database.connect
  rescue StandardError => e
    puts "Failed to connect: #{e.message}"
  ensure
    puts "Initialization complete"
  end
end
```

The `ensure` keyword is essential for writing robust Ruby code that properly manages resources and handles cleanup operations, regardless of whether exceptions occur. 