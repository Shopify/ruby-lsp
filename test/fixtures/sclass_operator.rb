class Foo
  class << self
    def bar; end
  end

  class << baz
    def qux; end
  end
end
