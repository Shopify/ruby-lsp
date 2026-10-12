# typed: true

module URI
  def self.register_scheme(scheme, klass); end

  class Generic
    PARSER = T.let(const_defined?(:RFC2396_PARSER) ? RFC2396_PARSER : DEFAULT_PARSER, RFC2396_Parser)

    sig { returns(T.nilable(String)) }
    def to_standardized_path; end

    sig { returns(T.nilable(String)) }
    def full_path; end

    sig do
      params(
        path: String,
        fragment: T.nilable(String),
        scheme: String,
        load_path_entry: T.nilable(String)
      ).returns(::URI::Generic)
    end
    def self.from_path(path:, fragment: nil, scheme: "file", load_path_entry: nil); end
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
