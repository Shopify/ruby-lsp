# typed: true

module URI
  def self.register_scheme(scheme, klass); end

  class Generic
    PARSER = T.let(const_defined?(:RFC2396_PARSER) ? RFC2396_PARSER : DEFAULT_PARSER, RFC2396_Parser)
  end

  class File
    attr_reader :path
  end

  class Source
    sig { returns(String) }
    attr_reader :host

    sig { returns(String) }
    attr_reader :fragment

    sig { returns(T.nilable(String)) }
    attr_accessor :line_number

    sig { returns(T.nilable(String)) }
    attr_accessor :gem_name
  end
end
