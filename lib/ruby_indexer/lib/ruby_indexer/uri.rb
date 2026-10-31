# typed: strict
# frozen_string_literal: true

require "uri"

module URI
  class Generic
    # Avoid a deprecation warning with Ruby 3.4 where the default parser was changed to RFC3986.
    # This condition must remain even after support for 3.4 has been dropped for users that have
    # `uri` in their lockfile, decoupling it from the ruby version.

    # NOTE: We also define this in the shim
    PARSER = const_defined?(:RFC2396_PARSER) ? RFC2396_PARSER : DEFAULT_PARSER

    # This unsafe regex is the same one used in the URI::RFC2396_REGEXP class with the exception of the fact that we
    # do not include colon as a safe character. VS Code URIs always escape colons and we need to ensure we do the
    # same to avoid inconsistencies in our URIs, which are used to identify resources
    UNSAFE_REGEX = %r{[^\-_.!~*'()a-zA-Z\d;/?@&=+$,\[\]]}

    class << self
      #: (path: String, ?fragment: String?, ?scheme: String, ?load_path_entry: String?) -> URI::Generic
      def from_win_path(path:, fragment: nil, scheme: "file", load_path_entry: nil)
        # On Windows, if the path begins with the disk name, we need to add a leading slash to make it a valid URI
        escaped_path = if /^[A-Z]:/i.match?(path)
          PARSER.escape("/#{path}", UNSAFE_REGEX)
        elsif path.start_with?("//?/")
          # Some paths on Windows start with "//?/". This is a special prefix that allows for long file paths
          PARSER.escape(path.delete_prefix("//?"), UNSAFE_REGEX)
        else
          PARSER.escape(path, UNSAFE_REGEX)
        end

        uri = build(scheme: scheme, path: escaped_path, fragment: fragment)

        if load_path_entry
          uri.require_path = path.delete_prefix("#{load_path_entry}/").delete_suffix(".rb")
        end

        uri
      end

      #: (path: String, ?fragment: String?, ?scheme: String, ?load_path_entry: String?) -> URI::Generic
      def from_unix_path(path:, fragment: nil, scheme: "file", load_path_entry: nil)
        escaped_path = PARSER.escape(path, UNSAFE_REGEX)

        uri = build(scheme: scheme, path: escaped_path, fragment: fragment)

        if load_path_entry
          uri.require_path = path.delete_prefix("#{load_path_entry}/").delete_suffix(".rb")
        end

        uri
      end

      alias_method :from_path, Gem.win_platform? ? :from_win_path : :from_unix_path
    end

    #: String?
    attr_accessor :require_path

    #: (String load_path_entry) -> void
    def add_require_path_from_load_entry(load_path_entry)
      path = to_standardized_path
      return unless path

      self.require_path = path.delete_prefix("#{load_path_entry}/").delete_suffix(".rb")
    end

    #: -> String?
    # On Windows, when we're getting the file system path back from the URI, we need to remove the leading forward
    # slash
    def to_standardized_win_path
      parsed_path = path

      return unless parsed_path

      # we can bail out parsing if there is nothing to unescape
      return parsed_path unless parsed_path.match?(/%[0-9A-Fa-f]{2}/)

      unescaped_path = PARSER.unescape(parsed_path)

      if %r{^/[A-Z]:}i.match?(unescaped_path)
        unescaped_path.delete_prefix("/")
      else
        unescaped_path
      end
    end

    #: -> String?
    def to_standardized_unix_path
      unescaped_path = path
      return unless unescaped_path

      # we can bail out parsing if there is nothing to be unescaped
      return unescaped_path unless unescaped_path.match?(/%[0-9A-Fa-f]{2}/)

      PARSER.unescape(unescaped_path)
    end

    alias_method :to_standardized_path, Gem.win_platform? ? :to_standardized_win_path : :to_standardized_unix_path
    alias_method :full_path, Gem.win_platform? ? :to_standardized_win_path : :to_standardized_unix_path
  end
end
