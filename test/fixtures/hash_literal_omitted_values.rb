module Foo
  hello = "world"
  {hello:}

  TEST = "something"
  {TEST:}

  def foo; end
  {foo:}

  def test(opts = {}); end
  test(foo:, TEST:, hello:)
end
