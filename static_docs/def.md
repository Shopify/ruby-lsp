# Def

In Ruby, the `def` keyword is used to define methods. Methods are reusable blocks of code that can accept parameters and return values. Every method implicitly returns the value of its last executed expression.

```ruby
# Basic method definition
def greet(name)
  "Hello, #{name}!"
end

puts greet("Ruby")
# Output:
# Hello, Ruby!
```

Methods can be defined with different types of parameters, including optional and keyword arguments.

```ruby
# Method with optional parameter
def calculate_total(amount, tax = 0.1)
  amount + (amount * tax)
end

puts calculate_total(100)      # Output: 110.0
puts calculate_total(100, 0.2) # Output: 120.0

# Method with keyword arguments
def create_user(name:, email:, role: "member")
  "#{name} (#{email}) - #{role}"
end

puts create_user(name: "Alice", email: "alice@example.com")
# Output: Alice (alice@example.com) - member
```

## Method Return Values

Methods return the value of their last expression by default, but can use an explicit `return` statement to exit early.

```ruby
def check_status(value)
  return "Invalid" if value < 0

  if value > 100
    "Too high"
  else
    "OK"
  end
end

puts check_status(-1)  # Output: Invalid
puts check_status(50)  # Output: OK
puts check_status(150) # Output: Too high
```

## Instance and Class Methods

Methods can be defined at both the instance and class level.

```ruby
class Timer
  # Instance method - called on instances
  def start
    @time = Time.now
    "Timer started"
  end

  # Class method - called on the class itself
  def self.now
    Time.now.strftime("%H:%M:%S")
  end
end

timer = Timer.new
puts timer.start     # Output: Timer started
puts Timer.now       # Output: 14:30:45
```

## Method Visibility

Methods can have different visibility levels using `private`, `protected`, or `public` (default).

```ruby
class BankAccount
  def initialize(balance)
    @balance = balance
  end

  def withdraw(amount)
    return "Insufficient funds" unless sufficient_funds?(amount)

    process_withdrawal(amount)
    "Withdrawn: $#{amount}"
  end

  private

  def sufficient_funds?(amount)
    @balance >= amount
  end

  def process_withdrawal(amount)
    @balance -= amount
  end
end

account = BankAccount.new(100)
puts account.withdraw(50) # Output: Withdrawn: $50
```

The `def` keyword is essential for organizing code into reusable, maintainable methods that form the building blocks of Ruby programs. 