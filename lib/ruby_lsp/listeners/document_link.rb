# typed: strict
# frozen_string_literal: true

require "ruby_lsp/requests/support/source_uri"

module RubyLsp
  module Listeners
    class DocumentLink
      extend T::Sig
      include Requests::Support::Common

      GEM_TO_VERSION_MAP = T.let(
        [*::Gem::Specification.default_stubs, *::Gem::Specification.stubs].map! do |s|
          [s.name, s.version.to_s]
        end.to_h.freeze,
        T::Hash[String, String],
      )

      class << self
        extend T::Sig

        sig { returns(T::Hash[String, T::Hash[String, T::Hash[String, String]]]) }
        def gem_paths
          @gem_paths ||= T.let(
            begin
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
            end,
            T.nilable(T::Hash[String, T::Hash[String, T::Hash[String, String]]]),
          )
        end
      end

      sig do
        params(
          response_builder: ResponseBuilders::CollectionResponseBuilder[Interface::DocumentLink],
          uri: URI::Generic,
          comments: T::Array[Prism::Comment],
          dispatcher: Prism::Dispatcher,
        ).void
      end
      def initialize(response_builder, uri, comments, dispatcher)
        # Match the version based on the version in the RBI file name. Notice that the `@` symbol is sanitized to `%40`
        # in the URI
        @response_builder = response_builder
        path = uri.to_standardized_path
        version_match = path ? /(?<=%40)[\d.]+(?=\.rbi$)/.match(path) : nil
        @gem_version = T.let(version_match && version_match[0], T.nilable(String))
        @lines_to_comments = T.let(
          comments.to_h do |comment|
            [comment.location.end_line, comment]
          end,
          T::Hash[Integer, Prism::Comment],
        )

        dispatcher.register(
          self,
          :on_def_node_enter,
          :on_class_node_enter,
          :on_module_node_enter,
          :on_constant_write_node_enter,
          :on_constant_path_write_node_enter,
        )
      end

      sig { params(node: Prism::DefNode).void }
      def on_def_node_enter(node)
        extract_document_link(node)
      end

      sig { params(node: Prism::ClassNode).void }
      def on_class_node_enter(node)
        extract_document_link(node)
      end

      sig { params(node: Prism::ModuleNode).void }
      def on_module_node_enter(node)
        extract_document_link(node)
      end

      sig { params(node: Prism::ConstantWriteNode).void }
      def on_constant_write_node_enter(node)
        extract_document_link(node)
      end

      sig { params(node: Prism::ConstantPathWriteNode).void }
      def on_constant_path_write_node_enter(node)
        extract_document_link(node)
      end

      private

      sig { params(node: Prism::Node).void }
      def extract_document_link(node)
        comment = @lines_to_comments[node.location.start_line - 1]
        return unless comment

        match = comment.location.slice.match(%r{source://.*#\d+$})
        return unless match

        uri = T.cast(URI(T.must(match[0])), URI::Source)
        gem_version = resolve_version(uri)
        return if gem_version.nil?

        path = uri.path
        return unless path

        gem_name = uri.gem_name
        return unless gem_name

        file_path = self.class.gem_paths.dig(gem_name, gem_version, CGI.unescape(path))
        return if file_path.nil?

        @response_builder << Interface::DocumentLink.new(
          range: range_from_location(comment.location),
          target: "file://#{file_path}##{uri.line_number}",
          tooltip: "Jump to #{file_path}##{uri.line_number}",
        )
      end

      # Try to figure out the gem version for a source:// link. The order of precedence is:
      # 1. The version in the URI
      # 2. The version in the RBI file name
      # 3. The version from the gemspec
      sig { params(uri: URI::Source).returns(T.nilable(String)) }
      def resolve_version(uri)
        version = uri.gem_version
        return version unless version.nil? || version.empty?

        return @gem_version unless @gem_version.nil? || @gem_version.empty?

        gem_name = uri.gem_name
        return unless gem_name

        GEM_TO_VERSION_MAP[gem_name]
      end
    end
  end
end
