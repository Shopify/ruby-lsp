# typed: strict
# frozen_string_literal: true

require "yaml"
require "did_you_mean"

require "ruby_indexer/lib/ruby_indexer/indexable_path"
require "ruby_indexer/lib/ruby_indexer/collector"
require "ruby_indexer/lib/ruby_indexer/index"
require "ruby_indexer/lib/ruby_indexer/entry"
require "ruby_indexer/lib/ruby_indexer/configuration"
require "ruby_indexer/lib/ruby_indexer/prefix_tree"

module RubyIndexer
  @configuration = T.let(Configuration.new, Configuration)

  class << self
    extend T::Sig

    sig { returns(Configuration) }
    attr_reader :configuration
  end
end
