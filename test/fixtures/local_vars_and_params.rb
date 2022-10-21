def foo(a, &block)
  b = a
  block.call
end
