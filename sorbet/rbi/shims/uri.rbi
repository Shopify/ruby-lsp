# typed: true

module URI
  def self.register_scheme(scheme, klass); end

  class File < Generic
    attr_reader :path
  end

  class Source
    sig { returns(String) }
    attr_reader :host

    sig { returns(String) }
    attr_reader :fragment
  end
end
