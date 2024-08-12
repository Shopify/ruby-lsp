# typed: true
# frozen_string_literal: true

# rubocop:enable Metrics/MethodLength
sig { void }
def very_complex_method
  if foo
    do_something
  else
    do_something_else
  end

  if bar
    do_the_same
  else
    do_something_different
  end

  baz
end
