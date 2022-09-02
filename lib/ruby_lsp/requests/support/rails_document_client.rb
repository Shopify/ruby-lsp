# typed: strict
# frozen_string_literal: true

module RubyLsp
  module Requests
    module Support
      class RailsDocumentClient
        RAILS_DOC_HOST = "https://api.rubyonrails.org"
        RAILS_DOC_PATHS_MAP = T.let(
          {
            "controllers" => Regexp.union(/ActionController/, /AbstractController/, /ActiveRecord/),
            "models" => Regexp.union(/ActiveRecord/, /ActiveModel/, /ActiveStorage/, /ActionText/),
            "config" => /ActionDispatch/,
            "jobs" => Regexp.union(/ActiveJob/, /ActiveRecord/),
          }.freeze, T::Hash[String, Regexp]
        )
        SUPPORTED_RAILS_DOC_NAMESPACES = T.let(
          Regexp.union(RAILS_DOC_PATHS_MAP.values).freeze,
          Regexp,
        )

        RAILTIES_VERSION = T.let(
          [*::Gem::Specification.default_stubs, *::Gem::Specification.stubs].find do |s|
            s.name == "railties"
          end&.version&.to_s, T.nilable(String)
        )

        class << self
          extend T::Sig
          sig { returns(T.nilable(T::Hash[String, T::Hash[Symbol, String]])) }
          def rails_documents
            @rails_documents ||= T.let(begin
              table = {}

              return table unless RAILTIES_VERSION

              $stderr.puts "Fetching Rails Documents..."
              # If the version's doc is not found, e.g. Rails main, it'll be redirected
              # In this case, we just fetch the latest doc
              response = if Gem::Version.new(RAILTIES_VERSION).prerelease?
                Net::HTTP.get_response(URI("#{RAILS_DOC_HOST}/js/search_index.js"))
              else
                Net::HTTP.get_response(URI("#{RAILS_DOC_HOST}/v#{RAILTIES_VERSION}/js/search_index.js"))
              end

              if response.code == "200"
                raw_data = response.body.sub("var search_data = ", "")
                data = JSON.parse(raw_data).dig("index", "info")

                # An entry looks like this:
                #
                # ["belongs_to",                                                              # method or module/class
                #  "ActiveRecord::Associations::ClassMethods",                                # method owner
                #  "classes/ActiveRecord/Associations/ClassMethods.html#method-i-belongs_to", # path to the document
                #  "(name, scope = nil, **options)",                                          # method's parameters
                #  "<p>Specifies a one-to-one association with another class..."]             # document preview
                #
                data.each do |ary|
                  doc_preview = ary[4]
                  # The 5th attribute is the method's document preview.
                  # If a method doesn't have documentation, there's no need to generate the link to it.
                  next if doc_preview.nil? || doc_preview.empty?

                  method_or_class = ary[0]
                  method_owner = ary[1]

                  # If the method or class/module is not from the supported namespace, reject it
                  next unless [method_or_class, method_owner].any? do |elem|
                                elem.match?(SUPPORTED_RAILS_DOC_NAMESPACES)
                              end

                  doc_path = ary[2]
                  owner = method_owner.empty? ? method_or_class : method_owner
                  table[method_or_class] = { owner: owner, path: doc_path }
                end
              else
                $stderr.puts("Response failed: #{response.inspect}")
              end

              table
            rescue StandardError => e
              $stderr.puts("Exception occurred when fetching Rails document index: #{e.inspect}")
              table
            end, T.nilable(T::Hash[String, T::Hash[Symbol, String]]))
          end

          sig do
            params(name: String, range: LanguageServer::Protocol::Interface::Range,
              file_dir: String).returns(T.nilable(LanguageServer::Protocol::Interface::DocumentLink))
          end
          def generate_rails_document_link(name, range, file_dir)
            doc = T.must(rails_documents)[name]

            return unless doc

            owner = doc[:owner]

            return unless RAILS_DOC_PATHS_MAP.any? do |folder, patterns|
              file_dir.match?(folder) && T.must(owner).match?(patterns)
            end

            tooltip_name =
              # class/module name
              if owner == name
                name
              else
                "#{owner}##{name}"
              end

            LanguageServer::Protocol::Interface::DocumentLink.new(
              range: range,
              target: "#{RAILS_DOC_HOST}/v#{RAILTIES_VERSION}/#{doc[:path]}",
              tooltip: "Browse the Rails documentation for: #{tooltip_name}",
            )
          end
        end
      end
    end
  end
end
