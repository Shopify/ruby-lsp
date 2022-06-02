[]
  .select do |x|
    if x.odd?
      x + 2
    else
      x + 1
    end
  end
  .map { |x| x }
  .drop(1)
  .sort
