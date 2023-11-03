def method
  a = 1
          -> { # rubocop:disable Layout/IndentationConsistency
          }.call

  a
end
