# typed: true

class Bundler::Settings
  sig { params(name: String).returns(String) }
  def self.key_for(name); end
end
