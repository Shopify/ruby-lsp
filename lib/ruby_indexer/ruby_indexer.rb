# typed: strict
# frozen_string_literal: true

require "yaml"
require "did_you_mean"

require "ruby_indexer/lib/ruby_indexer/indexable_path"
require "ruby_indexer/lib/ruby_indexer/visitor"
require "ruby_indexer/lib/ruby_indexer/index"
require "ruby_indexer/lib/ruby_indexer/configuration"
require "ruby_indexer/lib/ruby_indexer/prefix_tree"

module RubyIndexer
  class << self
    extend T::Sig

    sig { returns(Configuration) }
    def configuration
      @configuration ||= T.let(Configuration.new, T.nilable(Configuration))
    end
  end
end
