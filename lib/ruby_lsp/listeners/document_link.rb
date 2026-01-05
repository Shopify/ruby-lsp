# typed: strict
# frozen_string_literal: true

require "ruby_lsp/requests/support/source_uri"
require "ruby_lsp/requests/support/package_url"

module RubyLsp
  module Listeners
    class DocumentLink
      include Requests::Support::Common

      GEM_TO_VERSION_MAP = [*::Gem::Specification.default_stubs, *::Gem::Specification.stubs].map! do |s|
        [s.name, s.version.to_s]
      end.to_h.freeze #: Hash[String, String]

      class << self
        #: -> Hash[String, Hash[String, Hash[String, String]]]
        def gem_paths
          @gem_paths ||= begin
            lookup = {}

            Gem::Specification.stubs.each do |stub|
              spec = stub.to_spec
              lookup[spec.name] = {}
              lookup[spec.name][spec.version.to_s] = {}

              Dir.glob("**/*.rb", base: "#{spec.full_gem_path.delete_prefix("//?/")}/").each do |path|
                lookup[spec.name][spec.version.to_s][path] = "#{spec.full_gem_path}/#{path}"
              end
            end

            Gem::Specification.default_stubs.each do |stub|
              spec = stub.to_spec
              lookup[spec.name] = {}
              lookup[spec.name][spec.version.to_s] = {}
              prefix_matchers = Regexp.union(spec.require_paths.map do |rp|
                                               Regexp.new("^#{rp}/")
                                             end)
              prefix_matcher = Regexp.union(prefix_matchers, //)

              spec.files.each do |file|
                path = file.sub(prefix_matcher, "")
                lookup[spec.name][spec.version.to_s][path] = "#{RbConfig::CONFIG["rubylibdir"]}/#{path}"
              end
            end

            lookup
          end #: Hash[String, Hash[String, Hash[String, String]]]?
        end
      end

      #: (ResponseBuilders::CollectionResponseBuilder[Interface::DocumentLink] response_builder, URI::Generic uri, Array[Prism::Comment] comments, Prism::Dispatcher dispatcher) -> void
      def initialize(response_builder, uri, comments, dispatcher)
        # Match the version based on the version in the RBI file name. Notice that the `@` symbol is sanitized to `%40`
        # in the URI
        @response_builder = response_builder
        path = uri.to_standardized_path
        version_match = path ? /(?<=%40)[\d.]+(?=\.rbi$)/.match(path) : nil
        @gem_version = version_match && version_match[0] #: String?
        @lines_to_comments = comments.to_h do |comment|
          [comment.location.end_line, comment]
        end #: Hash[Integer, Prism::Comment]

        dispatcher.register(
          self,
          :on_def_node_enter,
          :on_class_node_enter,
          :on_module_node_enter,
          :on_constant_write_node_enter,
          :on_constant_path_write_node_enter,
        )
      end

      #: (Prism::DefNode node) -> void
      def on_def_node_enter(node)
        extract_document_link(node)
      end

      #: (Prism::ClassNode node) -> void
      def on_class_node_enter(node)
        extract_document_link(node)
      end

      #: (Prism::ModuleNode node) -> void
      def on_module_node_enter(node)
        extract_document_link(node)
      end

      #: (Prism::ConstantWriteNode node) -> void
      def on_constant_write_node_enter(node)
        extract_document_link(node)
      end

      #: (Prism::ConstantPathWriteNode node) -> void
      def on_constant_path_write_node_enter(node)
        extract_document_link(node)
      end

      private

      #: (Prism::Node node) -> void
      def extract_document_link(node)
        comment = @lines_to_comments[node.location.start_line - 1]
        return unless comment

        match = comment.location.slice.match(%r{(source://.*#\d+|pkg:gem/.*#.*)$})
        return unless match

        uri_string = match[0] #: as !nil

        file_path, line_number = if uri_string.start_with?("pkg:gem/")
          parse_package_url(uri_string)
        else
          parse_source_uri(uri_string)
        end

        return unless file_path

        @response_builder << Interface::DocumentLink.new(
          range: range_from_location(comment.location),
          target: "file://#{file_path}##{line_number}",
          tooltip: "Jump to #{file_path}##{line_number}",
        )
      end

      #: (String uri_string) -> [String, String]?
      def parse_package_url(uri_string)
        purl = PackageURL.parse(uri_string) #: as PackageURL?
        return unless purl

        gem_version = resolve_version(purl.version, purl.name)
        return if gem_version.nil?

        path, line_number = purl.subpath.split(":", 2)
        return unless path

        gem_name = purl.name
        file_path = self.class.gem_paths.dig(gem_name, gem_version, CGI.unescape(path))
        return if file_path.nil?

        [file_path, line_number]
      rescue PackageURL::InvalidPackageURL
        nil
      end

      #: (String uri_string) -> [String, String]?
      def parse_source_uri(uri_string)
        uri = begin
          URI(uri_string)
        rescue URI::Error
          nil
        end #: as URI::Source?
        return unless uri

        gem_version = resolve_version(uri.gem_version, uri.gem_name)
        return if gem_version.nil?

        path = uri.path
        return unless path

        file_path = self.class.gem_paths.dig(uri.gem_name, gem_version, CGI.unescape(path))
        return if file_path.nil?

        [file_path, uri.line_number || "0"]
      end

      # Try to figure out the gem version for a source:// link. The order of precedence is:
      # 1. The version in the URI
      # 2. The version in the RBI file name
      # 3. The version from the gemspec
      #: (String? version, String? gem_name) -> String?
      def resolve_version(version, gem_name)
        return version unless version.nil? || version.empty?

        return @gem_version unless @gem_version.nil? || @gem_version.empty?

        GEM_TO_VERSION_MAP[gem_name.to_s]
      end
    end
  end
end
