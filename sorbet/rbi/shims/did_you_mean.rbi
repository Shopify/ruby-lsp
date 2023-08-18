# typed: true

module DidYouMean::JaroWinkler
  sig { params(str1: String, str2: String).returns(Float) }
  def self.distance(str1, str2); end
end
