# typed: true

class Gem::Specification
  class << self
    sig { params(block: T.proc.params(spec: Gem::Specification).returns(T::Boolean)).returns(T::Boolean) }
    def any?(&block); end
  end
end
