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
    # These are inherited from `URI::File`.
    # We need to repeat them so Sorbet statically knows about them, so they can be aliased.

    sig { returns(String) }
    attr_reader :host

    sig { returns(T.nilable(String)) }
    attr_reader :fragment
  end
end
