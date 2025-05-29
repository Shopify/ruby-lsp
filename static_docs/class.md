# Class

In Ruby, a `class` is a blueprint for creating objects that share similar attributes and behaviors. Classes encapsulate data and methods, following object-oriented programming principles.

```ruby
# Basic class definition
class Person
  def initialize(name)
    @name = name
  end

  def greet
    puts "Hello, #{@name}!"
  end
end

person = Person.new("Ruby")
person.greet
# Output:
# Hello, Ruby!
```

Classes can include instance methods, class methods, and various types of variables.

```ruby
class Product
  # Class variable (shared across all instances)
  @@count = 0

  # Class method
  class << self
    def count
      @@count
    end
  end

  def initialize(name, price)
    @name = name
    @price = price
    @@count += 1
  end

  # Instance method
  def details
    "#{@name}: $#{@price}"
  end
end

book = Product.new("Ruby Guide", 29.99)
puts Product.count # Output: 1
puts book.details # Output: Ruby Guide: $29.99
```

## Inheritance

Classes can inherit behavior from other classes using the `<` operator. A class can only inherit from one parent class.

```ruby
# Parent class
class Animal
  def speak
    "Some sound"
  end
end

# Child class
class Dog < Animal
  def speak
    "Woof!"
  end
end

dog = Dog.new
puts dog.speak # Output: Woof!
```

## Access Control

Ruby provides three levels of method access control: `public`, `private`, and `protected`.

```ruby
class BankAccount
  def initialize(balance)
    @balance = balance
  end

  # Public method - can be called by anyone
  def display_balance
    "Current balance: $#{@balance}"
  end

  # Protected method - can be called by other instances
  protected

  def compare_balance(other)
    @balance > other.balance
  end

  # Private method - can only be called internally
  private

  def update_balance(amount)
    @balance += amount
  end
end

account = BankAccount.new(100)
puts account.display_balance
# Output: Current balance: $100
```

## Class Instance Variables

Instance variables can be exposed using attribute accessors. Ruby provides several methods to create them.

```ruby
class User
  # Create reader and writer methods
  attr_accessor :name

  # Create reader only
  attr_reader :created_at

  # Create writer only
  attr_writer :password

  def initialize(name)
    @name = name
    @created_at = Time.now
  end
end

user = User.new("Alice")
puts user.name # Output: Alice
user.name = "Bob"
puts user.name # Output: Bob
```

The `class` keyword is fundamental to Ruby's object-oriented nature, allowing you to create organized, reusable, and maintainable code through encapsulation, inheritance, and polymorphism.
