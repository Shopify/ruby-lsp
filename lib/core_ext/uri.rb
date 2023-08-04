# typed: strict
# frozen_string_literal: true

module URI
  class Generic
    class << self
      extend T::Sig

      sig { params(path: String, scheme: String).returns(URI::Generic) }
      def from_path(path:, scheme: "file")
        # On Windows, if the path begins with the disk name, we need to add a leading slash to make it a valid URI
        escaped_path = if /^[A-Z]:/.match?(path)
          DEFAULT_PARSER.escape("/#{path}")
        else
          DEFAULT_PARSER.escape(path)
        end

        build(scheme: scheme, path: escaped_path)
      end
    end

    extend T::Sig

    sig { returns(T.nilable(String)) }
    def to_standardized_path
      parsed_path = path
      return unless parsed_path

      # On Windows, when we're getting the file system path back from the URI, we need to remove the leading forward
      # slash
      actual_path = if %r{^/[A-Z]:}.match?(parsed_path)
        parsed_path.delete_prefix("/")
      else
        parsed_path
      end

      CGI.unescape(actual_path)
    end

    sig { returns(String) }
    def storage_key
      T.must(to_standardized_path || opaque)
    end
  end
end
