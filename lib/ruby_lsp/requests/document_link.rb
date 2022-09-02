# typed: strict
# frozen_string_literal: true

require "net/http"
require "ruby_lsp/requests/support/source_uri"
require "ruby_lsp/requests/support/rails_document_client"

module RubyLsp
  module Requests
    #
    # The [document link](https://microsoft.github.io/language-server-protocol/specification#textDocument_documentLink)
    # provides 2 different features:
    #
    # 1. Jump from source comment
    #
    # ![Document link demo](../../misc/document_link.gif)
    #
    # It makes `# source://PATH_TO_FILE#line` comments in a Ruby/RBI file clickable if the file exists.
    # When the user clicks the link, it'll open that location.
    #
    # # Example
    #
    # ```ruby
    # # source://syntax_tree/3.2.1/lib/syntax_tree.rb#51 <- it will be clickable and will take the user to that location
    # def format(source, maxwidth = T.unsafe(nil))
    # end
    # ```
    #
    # 2. Link to Rails DSL documentation
    #
    # ![Document link to Rails document demo](../../misc/document_link_rails_doc.gif)
    #
    # When detecting Rails DSLs under certain paths, like seeing `before_save :callback` in files under `models/`,
    # it makes the DSL call clickable. When clicking the link, the user will be taken to its API doc in browser.
    #
    # # Example
    #
    # ```ruby
    # class Post < ApplicationRecord
    #   before_save :do_something # before_save will be clickable to its API document
    #   validates :title # validates will also be clickable
    # end
    # ```
    class DocumentLink < BaseRequest
      extend T::Sig

      GEM_TO_VERSION_MAP = T.let(
        [*::Gem::Specification.default_stubs, *::Gem::Specification.stubs].map! do |s|
          [s.name, s.version.to_s]
        end.to_h.freeze,
        T::Hash[String, String],
      )

      class << self
        extend T::Sig

        sig { returns(T::Hash[String, T::Array[String]]) }
        def gem_paths
          @gem_paths ||= T.let(begin
            lookup = {}

            Gem::Specification.stubs.each do |stub|
              spec = stub.to_spec
              lookup[spec.name] = {}
              lookup[spec.name][spec.version.to_s] = {}

              Dir.glob("**/*.rb", base: "#{spec.full_gem_path}/").each do |path|
                lookup[spec.name][spec.version.to_s][path] = "#{spec.full_gem_path}/#{path}"
              end
            end

            Gem::Specification.default_stubs.each do |stub|
              spec = stub.to_spec
              lookup[spec.name] = {}
              lookup[spec.name][spec.version.to_s] = {}
              prefix_matchers = [//]
              prefix_matchers.concat(spec.require_paths.map { |rp| Regexp.new("^#{rp}/") })
              prefix_matcher = Regexp.union(prefix_matchers)

              spec.files.each do |file|
                path = file.sub(prefix_matcher, "")
                lookup[spec.name][spec.version.to_s][path] = "#{RbConfig::CONFIG["rubylibdir"]}/#{path}"
              end
            end

            lookup
          end, T.nilable(T::Hash[String, T::Array[String]]))
        end
      end

      sig { params(uri: String, document: Document).void }
      def initialize(uri, document)
        super(document)

        # Match the version based on the version in the RBI file name. Notice that the `@` symbol is sanitized to `%40`
        # in the URI
        version_match = /(?<=%40)[\d.]+(?=\.rbi$)/.match(uri)
        @gem_version = T.let(version_match && version_match[0], T.nilable(String))
        @file_dir = T.let(Pathname.new(uri).dirname.to_s, String)
        @links = T.let([], T::Array[LanguageServer::Protocol::Interface::DocumentLink])
      end

      sig { override.returns(T.all(T::Array[LanguageServer::Protocol::Interface::DocumentLink], Object)) }
      def run
        visit(@document.tree)
        @links
      end

      sig { override.params(node: SyntaxTree::Comment).void }
      def visit_comment(node)
        match = node.value.match(%r{source://.*#\d+$})
        return unless match

        uri = T.cast(URI(match[0]), URI::Source)
        gem_version = resolve_version(uri)
        file_path = self.class.gem_paths.dig(uri.gem_name, gem_version, uri.path)
        return if file_path.nil?

        @links << LanguageServer::Protocol::Interface::DocumentLink.new(
          range: range_from_syntax_tree_node(node),
          target: "file://#{file_path}##{uri.line_number}",
          tooltip: "Jump to #{file_path}##{uri.line_number}",
        )
      end

      sig { override.params(node: SyntaxTree::Command).void }
      def visit_command(node)
        message = node.message
        link = Support::RailsDocumentClient.generate_rails_document_link(
          message.value,
          range_from_syntax_tree_node(message),
          @file_dir,
        )

        @links << link if link
        super
      end

      sig { override.params(node: SyntaxTree::ConstPathRef).void }
      def visit_const_path_ref(node)
        constant_name = full_constant_name(node)
        link = Support::RailsDocumentClient.generate_rails_document_link(
          constant_name,
          range_from_syntax_tree_node(node),
          @file_dir,
        )

        @links << link if link
        super
      end

      private

      # Try to figure out the gem version for a source:// link. The order of precedence is:
      # 1. The version in the URI
      # 2. The version in the RBI file name
      # 3. The version from the gemspec
      sig { params(uri: URI::Source).returns(T.nilable(String)) }
      def resolve_version(uri)
        version = uri.gem_version
        return version unless version.nil? || version.empty?

        return @gem_version unless @gem_version.nil? || @gem_version.empty?

        GEM_TO_VERSION_MAP[uri.gem_name]
      end
    end
  end
end
