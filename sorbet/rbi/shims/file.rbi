# typed: true

class File
  class << self
    sig { params(path: String).returns(T::Boolean) }
    def absolute_path?(path); end
  end
end
