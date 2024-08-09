# typed: strict
# frozen_string_literal: true

module RubyIndexer
  # The indexer ResourceUri class is a specialization of the regular URI class. It includes convenience methods, special
  # handling to support Windows paths and simplifications for URI elements that are not used in an LSP context.
  #
  # For example, it does not do anything with the `host` portion of the URI, but we include a `require_path` attribute,
  # so that we know how this URI is mapped in the `$LOAD_PATH` if applicable
  class ResourceUri < URI::Generic
    class << self
      extend T::Sig

      sig { params(path: String, load_path_entry: T.nilable(String)).returns(FileUri) }
      def file(path, load_path_entry = nil)
        require_path = if load_path_entry
          rp = path.delete_prefix("#{load_path_entry}/")
          rp.delete_suffix!(".rb")
          rp
        end

        FileUri.new(path: path, require_path: require_path)
      end
    end

    extend T::Sig

    sig { returns(T.nilable(String)) }
    attr_reader :require_path

    sig do
      params(
        scheme: T.nilable(String),
        path: T.nilable(String),
        opaque: T.nilable(String),
        fragment: T.nilable(String),
        require_path: T.nilable(String),
      ).void
    end
    def initialize(scheme: "file", path: nil, opaque: nil, fragment: nil, require_path: nil)
      # On Windows, if the path begins with the disk name, we need to add a leading slash to make it a valid URI
      escaped_path = if !path
        nil
      elsif /^[A-Z]:/i.match?(path)
        URI::DEFAULT_PARSER.escape("/#{path}")
      elsif path.start_with?("//?/")
        # Some paths on Windows start with "//?/". This is a special prefix that allows for long file paths
        URI::DEFAULT_PARSER.escape(path.delete_prefix("//?"))
      else
        URI::DEFAULT_PARSER.escape(path)
      end

      # scheme, userinfo, host, port, registry, path, opaque, query, fragment, parser, arg_check
      super(scheme, nil, nil, nil, nil, escaped_path, opaque, nil, fragment, URI::DEFAULT_PARSER, true)
      @require_path = require_path
    end

    sig { returns(String) }
    def to_s
      "#{@scheme}://#{@path || @opaque}"
    end

    sig { returns(String) }
    def to_s_with_fragment
      str = to_s
      return str unless @fragment

      "#{str}##{@fragment}"
    end

    sig { returns(T.nilable(String)) }
    def to_standardized_path
      parsed_path = @path
      return unless parsed_path

      unescaped_path = URI::DEFAULT_PARSER.unescape(parsed_path)

      # On Windows, when we're getting the file system path back from the URI, we need to remove the leading forward
      # slash
      if %r{^/[A-Z]:}i.match?(unescaped_path)
        unescaped_path.delete_prefix("/")
      else
        unescaped_path
      end
    end
  end

  class FileUri < ResourceUri
    extend T::Sig

    sig { override.returns(String) }
    def to_standardized_path
      parsed_path = T.must(@path)
      unescaped_path = URI::DEFAULT_PARSER.unescape(parsed_path)

      # On Windows, when we're getting the file system path back from the URI, we need to remove the leading forward
      # slash
      if %r{^/[A-Z]:}i.match?(unescaped_path)
        unescaped_path.delete_prefix("/")
      else
        unescaped_path
      end
    end
  end
end
