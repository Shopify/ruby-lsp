# Undef

The `undef` keyword in Ruby is used to undefine methods. When a method is undefined, any subsequent attempts to call it will result in a `NoMethodError`. This is different from making a method private or protected - the method is completely removed from the class.

```ruby
class Example
  def hello
    "Hello!"
  end
  
  def goodbye
    "Goodbye!"
  end
  
  # Undefine the hello method
  undef hello
end

example = Example.new
example.goodbye # => "Goodbye!"
example.hello   # => NoMethodError: undefined method `hello' for #<Example:0x...>
```

## Multiple methods

You can undefine multiple methods at once by providing multiple method names:

```ruby
class Greeter
  def hello
    "Hello!"
  end
  
  def hi
    "Hi!"
  end
  
  def hey
    "Hey!"
  end
  
  # Undefine multiple methods at once
  undef hello, hi, hey
end
```

## Common use cases

The `undef` keyword is often used when:
1. You want to prevent a method inherited from a superclass from being called
2. You want to ensure certain methods cannot be called on instances of your class
3. You're implementing a strict interface and want to remove methods that don't belong

```ruby
class RestrictedArray < Array
  # Prevent destructive methods from being called
  undef push, <<, pop, shift, unshift
end

restricted = RestrictedArray.new([1, 2, 3])
restricted.push(4) # => NoMethodError: undefined method `push' for #<RestrictedArray:0x...>
``` 