class Foo
  @@bar = 1

  def self.bar
    @@bar
  end
end

:@@bar # ignore
