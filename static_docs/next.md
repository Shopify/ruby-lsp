# Next

In Ruby, the `next` keyword is used to skip the rest of the current iteration and move to the next iteration of a loop or block. It's similar to `continue` in other programming languages.

```ruby
# Basic next usage in a loop
["README.md", ".git", "lib", ".gitignore"].each do |path|
  next if path.start_with?(".")
  puts "Processing: #{path}"
end
# Output:
# Processing: README.md
# Processing: lib
```

The `next` statement can be used with any of Ruby's iteration methods or blocks.

```ruby
# Using next with different iterators
users = [
  { name: "Alice", active: true },
  { name: "Bob", active: false },
  { name: "Carol", active: true }
]

# With each
users.each do |user|
  next unless user[:active]
  puts "Notifying #{user[:name]}"
end
# Output:
# Notifying Alice
# Notifying Carol

# With map
messages = users.map do |user|
  next "Account inactive" unless user[:active]
  "Welcome back, #{user[:name]}!"
end
puts messages.inspect
# Output:
# ["Welcome back, Alice!", "Account inactive", "Welcome back, Carol!"]
```

## Conditional Next

The `next` keyword is often used with conditions to create more complex iteration logic.

```ruby
# Processing specific elements
orders = [
  { id: 1, status: "paid" },
  { id: 2, status: "pending" },
  { id: 3, status: "cancelled" },
  { id: 4, status: "paid" }
]

orders.each do |order|
  # Skip non-paid orders
  next unless order[:status] == "paid"
  puts "Processing payment for order #{order[:id]}"
end
# Output:
# Processing payment for order 1
# Processing payment for order 4

# Processing with multiple conditions
products = [
  { name: "Book", price: 15, in_stock: true },
  { name: "Shirt", price: 25, in_stock: false },
  { name: "Hat", price: 12, in_stock: true }
]

products.each do |product|
  next unless product[:in_stock]    # Skip out of stock items
  next if product[:price] > 20      # Skip expensive items
  puts "Featured item: #{product[:name]} at $#{product[:price]}"
end
# Output:
# Featured item: Book at $15
# Featured item: Hat at $12
```

The `next` keyword helps control the flow of iterations, allowing you to skip unwanted elements or conditions while continuing the loop. 