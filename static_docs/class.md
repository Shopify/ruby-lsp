# Class

In Ruby, a `class` is a blueprint for creating objects that encapsulate related state and behavior. Each instance of a class has its own set of instance variables and methods, allowing objects to maintain their individual state.

```ruby
# Basic class definition
class Person
  def initialize(name)
    @name = name # Instance variable stores state
  end

  def greet # Instance method stores behavior
    puts "Hello, #{@name}!"
  end
end

person = Person.new("Ruby")
person.greet
# Output:
# Hello, Ruby!
```

## Instance Variables and Methods

Instance variables (starting with `@`) store object-specific state, while instance methods define the behavior that each object can perform.

```ruby
class BankAccount
  def initialize(balance)
    @balance = balance
  end

  def deposit(amount)
    @balance += amount
  end

  def current_balance
    @balance
  end
end

account = BankAccount.new(100)
account.deposit(50)
puts account.current_balance # Output: 150
```

## Attribute Accessors

Ruby provides convenient methods to create getters and setters for instance variables:

```ruby
class User
  # Creates both getter and setter methods
  attr_accessor :name

  # Creates getter method only
  attr_reader :created_at

  # Creates setter method only
  attr_writer :password

  def initialize(name)
    @name = name
    @created_at = Time.now
  end
end

user = User.new("Alice")
puts user.name        # Using getter (Output: Alice)
user.name = "Bob"     # Using setter
puts user.name        # Output: Bob
puts user.created_at  # Using reader
user.password = "123" # Using writer
```

## Inheritance

Classes can inherit behavior from other classes using the `<` operator, allowing for code reuse and specialization.

```ruby
class Animal
  def initialize(name)
    @name = name
  end

  def speak
    "Some sound"
  end
end

class Dog < Animal
  def speak
    "#{@name} says: Woof!"
  end
end

dog = Dog.new("Rex")
puts dog.speak # Output: Rex says: Woof!
```

The `class` keyword is fundamental to Ruby's object-oriented nature, allowing you to create organized, reusable code by grouping related data and behavior into objects.
