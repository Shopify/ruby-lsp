if %r{
  (?<one>\\w+)-
  (?<two>\\w+)
} =~ "something-else"
  one
  two
end
