# typed: strict
# frozen_string_literal: true

require "uri/file"

module URI
  # Must be kept in sync with the one in Tapioca
  class Source < URI::File
    extend T::Sig

    COMPONENT = T.let(
      [
        :scheme,
        :gem_name,
        :gem_version,
        :path,
        :line_number,
      ].freeze,
      T::Array[Symbol],
    )

    # `uri` for Ruby 3.4 switched the default parser from RFC2396 to RFC3986. The new parser emits a deprecation
    # warning on a few methods and delegates them to RFC2396, namely `extract`/`make_regexp`/`escape`/`unescape`.
    # On earlier versions of the uri gem, the RFC2396_PARSER constant doesn't exist, so it needs some special
    # handling to select a parser that doesn't emit deprecations. While it was backported to Ruby 3.1, users may
    # have the uri gem in their own bundle and thus not use a compatible version.
    PARSER = T.let(const_defined?(:RFC2396_PARSER) ? RFC2396_PARSER : DEFAULT_PARSER, RFC2396_Parser)

    T.unsafe(self).alias_method(:gem_name, :host)
    T.unsafe(self).alias_method(:line_number, :fragment)

    sig { returns(T.nilable(String)) }
    attr_reader :gem_version

    class << self
      extend T::Sig

      sig do
        params(
          gem_name: String,
          gem_version: T.nilable(String),
          path: String,
          line_number: T.nilable(String),
        ).returns(URI::Source)
      end
      def build(gem_name:, gem_version:, path:, line_number:)
        super(
          {
            scheme: "source",
            host: gem_name,
            path: PARSER.escape("/#{gem_version}/#{path}"),
            fragment: line_number,
          }
        )
      end
    end

    sig { params(v: T.nilable(String)).void }
    def set_path(v) # rubocop:disable Naming/AccessorMethodName
      return if v.nil?

      gem_version, path = v.delete_prefix("/").split("/", 2)

      @gem_version = T.let(gem_version, T.nilable(String))
      @path = T.let(path, T.nilable(String))
    end

    sig { params(v: T.nilable(String)).returns(T::Boolean) }
    def check_host(v)
      return true unless v

      if /[A-Za-z][A-Za-z0-9\-_]*/ !~ v
        raise InvalidComponentError,
          "bad component(expected gem name): #{v}"
      end

      true
    end

    sig { returns(String) }
    def to_s
      "source://#{gem_name}/#{gem_version}#{path}##{line_number}"
    end

    if URI.respond_to?(:register_scheme)
      URI.register_scheme("SOURCE", self)
    else
      @@schemes = T.let(@@schemes, T::Hash[String, T.untyped]) # rubocop:disable Style/ClassVars
      @@schemes["SOURCE"] = self
    end
  end
end
