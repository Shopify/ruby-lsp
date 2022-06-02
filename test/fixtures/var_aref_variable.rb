def my_method
  a = :hello # local variable arefs should match
  @my_ivar = true # ivar arefs should not match
  $global_var = 1  # global arefs should not match
  @@class_var = "hello" # cvar refs should not match
end
Foo = 3.14 # constant refs should not match
