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

    class << self
      #: (path: String, ?fragment: String?, ?scheme: String, ?load_path_entry: String?) -> URI::Generic
      def from_path(path:, fragment: nil, scheme: "file", load_path_entry: nil)
        # On Windows, if the path begins with the disk name, we need to add a leading slash to make it a valid URI
        escaped_path = if /^[A-Z]:/i.match?(path)
          PARSER.escape("/#{path}")
        elsif path.start_with?("//?/")
          # Some paths on Windows start with "//?/". This is a special prefix that allows for long file paths
          PARSER.escape(path.delete_prefix("//?"))
        else
          PARSER.escape(path)
        end

        uri = build(scheme: scheme, path: escaped_path, fragment: fragment)

        if load_path_entry
          uri.require_path = path.delete_prefix("#{load_path_entry}/").delete_suffix(".rb")
        end

        uri
      end
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
    def to_standardized_path
      parsed_path = path
      return unless parsed_path

      unescaped_path = PARSER.unescape(parsed_path)

      # On Windows, when we're getting the file system path back from the URI, we need to remove the leading forward
      # slash
      if %r{^/[A-Z]:}i.match?(unescaped_path)
        unescaped_path.delete_prefix("/")
      else
        unescaped_path
      end
    end

    alias_method :full_path, :to_standardized_path
  end
end
