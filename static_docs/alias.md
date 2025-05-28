# Alias

In Ruby, the `alias` keyword creates an alternative name for an existing method or constant. This allows you to call the same method using different names, which is particularly useful for method deprecation, creating shortcuts, or improving code readability.

```ruby
# Basic method aliasing
class User
  def full_name
    "#{first_name} #{last_name}"
  end

  alias name full_name
end

user = User.new
user.full_name # => "John Smith"
user.name      # => "John Smith"
```

When you create an alias, it creates a copy of the method at the time the alias is defined. This means that if you later modify the original method, the alias will still use the old version.

```ruby
class Calculator
  def add(a, b)
    a + b
  end

  alias plus add

  # Modifying the original method
  def add(a, b)
    puts "Adding #{a} and #{b}"
    a + b
  end
end

calc = Calculator.new
calc.plus(2, 3)  # => 5 (no output)
calc.add(2, 3)   # Prints "Adding 2 and 3" then returns 5
```

## Using alias_method

Ruby also provides `alias_method`, which is more flexible as it can accept dynamic method names and is more commonly used in modern Ruby:

```ruby
class Service
  def process_data
    puts "Processing..."
  end

  # Using alias_method with symbols
  alias_method :execute, :process_data

  # Can also use strings
  alias_method "run", "process_data"
end

service = Service.new
service.process_data # => "Processing..."
service.execute      # => "Processing..."
service.run         # => "Processing..."
```

## Common Use Cases

### Method Deprecation

```ruby
class API
  def fetch_users
    # New implementation
    User.all.includes(:preferences)
  end

  alias get_users fetch_users
  
  def get_users
    warn "[DEPRECATED] `get_users` is deprecated. Please use `fetch_users` instead"
    fetch_users
  end
end
```

### Creating Shorter Names

```ruby
class StringUtils
  def self.convert_to_uppercase(text)
    text.upcase
  end

  class << self
    alias up convert_to_uppercase
  end
end

StringUtils.convert_to_uppercase("hello") # => "HELLO"
StringUtils.up("hello")                  # => "HELLO"
```

### Aliasing Operators

```ruby
class Vector
  def initialize(x, y)
    @x = x
    @y = y
  end

  def add(other)
    Vector.new(@x + other.x, @y + other.y)
  end

  # Make + work the same as add
  alias + add

  protected

  attr_reader :x, :y
end

v1 = Vector.new(1, 2)
v2 = Vector.new(3, 4)
v3 = v1 + v2 # Same as v1.add(v2)
```

Remember that while aliasing can be useful, it should be used judiciously. Too many aliases can make code harder to understand and maintain. It's best used for:
- Creating more intuitive method names
- Supporting backward compatibility
- Implementing operator overloading
- Creating shortcuts for frequently used methods 