def foo
  a = 18
  case [1, 2]
  in ^a, *rest
    puts a
    puts rest
  end
end
