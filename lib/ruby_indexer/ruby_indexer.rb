# typed: strict
# frozen_string_literal: true

require "yaml"

require "ruby_indexer/lib/ruby_indexer/visitor"
require "ruby_indexer/lib/ruby_indexer/index"
require "ruby_indexer/lib/ruby_indexer/configuration"

module RubyIndexer
  class << self
    extend T::Sig

    sig { void }
    def load_configuration_file
      return unless File.exist?(".index.yml")

      config = YAML.parse_file(".index.yml")
      configuration.apply_config(config.to_ruby) if config
    end

    sig { returns(Configuration) }
    def configuration
      @configuration ||= T.let(Configuration.new, T.nilable(Configuration))
    end
  end
end
