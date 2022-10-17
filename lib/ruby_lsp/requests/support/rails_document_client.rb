# typed: strict
# frozen_string_literal: true

require "net/http"

module RubyLsp
  module Requests
    module Support
      class RailsDocumentClient
        RAILS_DOC_HOST = "https://api.rubyonrails.org"
        SUPPORTED_RAILS_DOC_NAMESPACES = T.let(
          Regexp.union(
            /ActionDispatch/, /ActionController/, /AbstractController/, /ActiveRecord/, /ActiveModel/, /ActiveStorage/,
            /ActionText/, /ActiveJob/
          ).freeze,
          Regexp,
        )

        RAILTIES_VERSION = T.let(
          [*::Gem::Specification.default_stubs, *::Gem::Specification.stubs].find do |s|
            s.name == "railties"
          end&.version&.to_s, T.nilable(String)
        )

        class << self
          extend T::Sig
          sig do
            params(name: String).returns(T::Array[String])
          end
          def generate_rails_document_urls(name)
            docs = search_index&.fetch(name, nil)

            return [] unless docs

            docs.map do |doc|
              owner = doc[:owner]

              link_name =
                # class/module name
                if owner == name
                  name
                else
                  "#{owner}##{name}"
                end

              "[Rails Document: `#{link_name}`](#{doc[:url]})"
            end
          end

          sig { returns(T.nilable(T::Hash[String, T::Array[T::Hash[Symbol, String]]])) }
          private def search_index
            @rails_documents ||= T.let(
              build_search_index,
              T.nilable(T::Hash[String, T::Array[T::Hash[Symbol, String]]]),
            )
          end

          sig { returns(T.nilable(T::Hash[String, T::Array[T::Hash[Symbol, String]]])) }
          private def build_search_index
            return unless RAILTIES_VERSION

            $stderr.puts "Fetching Rails Documents..."
            # If the version's doc is not found, e.g. Rails main, it'll be redirected
            # In this case, we just fetch the latest doc
            response = if Gem::Version.new(RAILTIES_VERSION).prerelease?
              Net::HTTP.get_response(URI("#{RAILS_DOC_HOST}/js/search_index.js"))
            else
              Net::HTTP.get_response(URI("#{RAILS_DOC_HOST}/v#{RAILTIES_VERSION}/js/search_index.js"))
            end

            if response.code == "200"
              process_search_index(response.body)
            else
              $stderr.puts("Response failed: #{response.inspect}")
              nil
            end
          rescue StandardError => e
            $stderr.puts("Exception occurred when fetching Rails document index: #{e.inspect}")
          end

          sig { params(js: String).returns(T::Hash[String, T::Array[T::Hash[Symbol, String]]]) }
          private def process_search_index(js)
            raw_data = js.sub("var search_data = ", "")
            info = JSON.parse(raw_data).dig("index", "info")

            # An entry looks like this:
            #
            # ["belongs_to",                                                              # method or module/class
            #  "ActiveRecord::Associations::ClassMethods",                                # method owner
            #  "classes/ActiveRecord/Associations/ClassMethods.html#method-i-belongs_to", # path to the document
            #  "(name, scope = nil, **options)",                                          # method's parameters
            #  "<p>Specifies a one-to-one association with another class..."]             # document preview
            #
            info.each_with_object({}) do |(method_or_class, method_owner, doc_path, _, doc_preview), table|
              # If a method doesn't have documentation, there's no need to generate the link to it.
              next if doc_preview.nil? || doc_preview.empty?

              # If the method or class/module is not from the supported namespace, reject it
              next unless [method_or_class, method_owner].any? do |elem|
                            elem.match?(SUPPORTED_RAILS_DOC_NAMESPACES)
                          end

              owner = method_owner.empty? ? method_or_class : method_owner
              table[method_or_class] ||= []
              # It's possible to have multiple modules defining the same method name. For example,
              # both `ActiveRecord::FinderMethods` and `ActiveRecord::Associations::CollectionProxy` defines `#find`
              table[method_or_class] << { owner: owner, url: "#{RAILS_DOC_HOST}/v#{RAILTIES_VERSION}/#{doc_path}" }
            end
          end
        end
      end
    end
  end
end
