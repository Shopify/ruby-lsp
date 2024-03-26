# typed: strict
# frozen_string_literal: true

module RubyLsp
  class Configuration
    extend T::Sig

    sig { params(workspace_uri: URI::Generic).void }
    def initialize(workspace_uri)
      @workspace_uri = workspace_uri
    end

    sig { returns(T::Hash[String, T.untyped]) }
    def indexing
      # Need to use the workspace URI, otherwise, this will fail for people working on a project that is a symlink.
      index_path = File.join(@workspace_uri.to_standardized_path, ".index.yml")
      ruby_lsp_path = File.join(@workspace_uri.to_standardized_path, ".ruby-lsp.yml")

      if File.exist?(index_path)
        unless ENV["RUBY_LSP_ENV"] == "test"
          $stderr.puts("The .index.yml configuration file is deprecated. Please rename it to .ruby-lsp.yml and " \
            "update the structure as described in the README: https://github.com/Shopify/ruby-lsp#configuration")
        end
        YAML.parse_file(index_path).to_ruby
      elsif File.exist?(ruby_lsp_path)
        YAML.parse_file(ruby_lsp_path).to_ruby.fetch("indexing")
      else
        {}
      end
    end
  end
end
