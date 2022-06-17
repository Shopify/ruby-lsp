def foo(a, b = 1, *c, d, e: 1, **f, &blk)
  puts a, b, c, d, e, f, blk
end
