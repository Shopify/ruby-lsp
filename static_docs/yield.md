# Yield

In Ruby, every method implicitly accepts a block, even when not included in the parameters list.

```ruby
def foo
end

foo { 123 } # works!
```

The `yield` keyword is used to invoke the block that was passed with arguments.

```ruby
# Consider this method call. The block being passed to the method `foo` accepts an argument called `a`.
# It then takes whatever argument was passed and multiplies it by 2
foo do |a|
  a * 2
end

# In the `foo` method declaration, we can use `yield` to invoke the block that was passed and provide the block
# with the value for the `a` argument
def foo
  # Invoke the block passed to `foo` with the number 10 as the argument `a`
  result = yield(10)
  puts result # Will print 20
end
```

If `yield` is used to invoke the block, but no block was passed, that will result in a local jump error.

```ruby
# If we invoke `foo` without a block, trying to `yield` will fail
foo

# `foo': no block given (yield) (LocalJumpError)
```

We can decide to use `yield` conditionally by using Ruby's `block_given?` method, which will return `true` if a block
was passed to the method.

```ruby
def foo
  # If a block is passed when invoking `foo`, call the block with argument 10 and print the result.
  # Otherwise, just print that no block was passed
  if block_given?
    result = yield(10)
    puts result
  else
    puts "No block passed!"
  end
end

foo do |a|
  a * 2
end
# => 20

foo
# => No block passed!
```

## Block parameter

In addition to implicit blocks, Ruby also allows developers to use explicit block parameters as part of the method's
signature. In this scenario, we can use the reference to the block directly instead of relying on the `yield` keyword.

```ruby
# Block parameters are prefixed with & and a name
def foo(&my_block_param)
  # If a block was passed to `foo`, `my_block_param` will be a `Proc` object. Otherwise, it will be `nil`. We can use
  # that to check for its presence
  if my_block_param
    # Explicit block parameters are invoked using the method `call`, which is present in all `Proc` objects
    result = my_block_param.call(10)
    puts result
  else
    puts "No block passed!"
  end
end
```
