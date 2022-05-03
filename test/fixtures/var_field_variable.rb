def my_method
  b = Foo # constant refs should not match
  a = true # keyword refs should not match
  a = @my_ivar # ivar refs should not match
  a = $global_var # global refs should not match
  a = @@class_var # cvar refs should not match
  a = b # local variable refs should match
end
