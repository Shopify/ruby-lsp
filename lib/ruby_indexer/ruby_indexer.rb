# typed: strict
# frozen_string_literal: true

require "ruby_indexer/lib/ruby_indexer/visitor"
require "ruby_indexer/lib/ruby_indexer/index"
require "ruby_indexer/lib/ruby_indexer/configuration"

module RubyIndexer
  class << self
    extend T::Sig

    sig { params(block: T.proc.params(configuration: Configuration).void).void }
    def configure(&block)
      block.call(configuration)
    end

    sig { returns(Configuration) }
    def configuration
      @configuration ||= T.let(Configuration.new, T.nilable(Configuration))
    end

    sig { params(paths: T::Array[String]).returns(Index) }
    def index(paths = configuration.files_to_index)
      index = Index.new
      paths.each { |path| index_single(index, path) }
      index
    end

    sig { params(index: Index, path: String, source: T.nilable(String)).void }
    def index_single(index, path, source = nil)
      content = source || File.read(path)
      visitor = IndexVisitor.new(index, YARP.parse(content), path)
      visitor.run
    end
  end
end
