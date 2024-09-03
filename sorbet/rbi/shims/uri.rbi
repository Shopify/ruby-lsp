# typed: true

module URI
  def self.register_scheme(scheme, klass); end

  class Generic
    def initialize(
      scheme,
      userinfo, host, port, registry,
      path, opaque,
      query,
      fragment,
      parser = DEFAULT_PARSER,
      arg_check = false)
      @scheme = T.let(T.unsafe(nil), String)
      @path = T.let(T.unsafe(nil), T.nilable(String))
      @opaque = T.let(T.unsafe(nil), T.nilable(String))
      @fragment = T.let(T.unsafe(nil), T.nilable(String))
   end
  end

  class File
    attr_reader :path
  end

  class Source
    sig { returns(String) }
    attr_reader :host

    sig { returns(String) }
    attr_reader :fragment
  end

  class WS; end
end
