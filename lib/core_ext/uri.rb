# typed: strict
# frozen_string_literal: true

module URI
  class Generic
    class << self
      extend T::Sig

      sig { params(path: String, fragment: T.nilable(String), scheme: String).returns(URI::Generic) }
      def from_path(path:, fragment: nil, scheme: "file")
        # On Windows, if the path begins with the disk name, we need to add a leading slash to make it a valid URI
        escaped_path = if /^[A-Z]:/i.match?(path)
          DEFAULT_PARSER.escape("/#{path}")
        else
          DEFAULT_PARSER.escape(path)
        end

        build(scheme: scheme, path: escaped_path, fragment: fragment)
      end
    end

    extend T::Sig

    sig { returns(T.nilable(String)) }
    def to_standardized_path
      parsed_path = path
      return unless parsed_path

      unescaped_path = DEFAULT_PARSER.unescape(parsed_path)

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
