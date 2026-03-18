# typed: strict
# frozen_string_literal: true

require "yaml"
require "did_you_mean"

require "ruby_indexer/lib/ruby_indexer/uri"
require "ruby_indexer/lib/ruby_indexer/visibility_scope"
require "ruby_indexer/lib/ruby_indexer/declaration_listener"
require "ruby_indexer/lib/ruby_indexer/reference_finder"
require "ruby_indexer/lib/ruby_indexer/enhancement"
require "ruby_indexer/lib/ruby_indexer/index"
require "ruby_indexer/lib/ruby_indexer/entry"
require "ruby_indexer/lib/ruby_indexer/configuration"
require "ruby_indexer/lib/ruby_indexer/prefix_tree"
require "ruby_indexer/lib/ruby_indexer/location"
require "ruby_indexer/lib/ruby_indexer/rbs_indexer"

module RubyIndexer
  class << self
    # The current configuration, shared across all entries to avoid per-instance storage overhead.
    # Set by Index#initialize. Thread-safe because the GVL ensures only one thread writes at a time.
    #: Configuration?
    attr_accessor :current_configuration
  end
end
