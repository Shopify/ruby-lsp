# Module

In Ruby, the `module` keyword creates a container for methods and constants. Modules serve two primary purposes: namespacing related code and providing reusable behavior through mixins.

```ruby
# Basic module definition
module Formatter
  def self.titleize(text)
    text.split.map(&:capitalize).join(" ")
  end
end

puts Formatter.titleize("hello world")
# Output:
# Hello World
```

Modules can be included in classes to share behavior through mixins, allowing for code reuse without inheritance.

```ruby
# Module as a mixin
module Printable
  def print_details
    puts "Name: #{name}"
    puts "ID: #{id}"
  end
end

class Product
  include Printable
  attr_reader :name, :id

  def initialize(name, id)
    @name = name
    @id = id
  end
end

book = Product.new("Ruby Guide", "B123")
book.print_details
# Output:
# Name: Ruby Guide
# ID: B123
```

## Namespacing

Modules help organize code by grouping related classes and methods under a namespace.

```ruby
module Shop
  class Product
    def initialize(name)
      @name = name
    end
  end

  class Order
    def initialize(product)
      @product = product
    end
  end
end

# Using namespaced classes
product = Shop::Product.new("Coffee")
order = Shop::Order.new(product)
```

## Multiple Includes

A class can include multiple modules to compose different behaviors.

```ruby
module Validatable
  def valid?
    !name.nil? && !id.nil?
  end
end

module Displayable
  def display
    "#{name} (#{id})"
  end
end

class Item
  include Validatable
  include Displayable

  attr_reader :name, :id

  def initialize(name, id)
    @name = name
    @id = id
  end
end

item = Item.new("Laptop", "L456")
puts item.valid?    # Output: true
puts item.display   # Output: Laptop (L456)
```

The `module` keyword is essential for organizing code and implementing Ruby's version of multiple inheritance through mixins. 