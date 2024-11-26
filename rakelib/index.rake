# frozen_string_literal: true

require "sorbet-runtime"
require "ruby_lsp/internal"

# Based on https://github.com/ruby/prism/blob/main/rakelib/lex.rake

module GemIndexing
  class << self
    # This method is responsible for iterating through a list of items and running
    # each item in a separate thread. It will block until all items have been
    # processed. This is particularly useful for tasks that are IO-bound like
    # downloading files or reading files from disk.
    def parallelize(items, &block)
      Thread.abort_on_exception = true

      queue = Queue.new
      items.each { |item| queue << item }

      workers =
        ENV.fetch("WORKERS") { 16 }.to_i.times.map do
          parallelize_thread(queue, &block)
        end

      workers.map(&:join)
    end

    private

    # Create a new thread with a minimal number of locals that it can access.
    def parallelize_thread(queue, &block)
      Thread.new { block.call(queue.shift) until queue.empty? }
    end
  end
end

TOP_100_GEM_FILENAME = "rakelib/top_100_gems.yml"
TOP_100_GEMS_DIR = "tmp/top_100_gems"

namespace :download do
  directory TOP_100_GEMS_DIR

  desc "Download the top 100 rubygems under #{TOP_100_GEMS_DIR}/"
  task topgems: TOP_100_GEMS_DIR do
    $LOAD_PATH.unshift(File.expand_path("../lib", __dir__))
    require "net/http"
    require "rubygems/package"
    require "tmpdir"

    GemIndexing.parallelize(YAML.safe_load_file(TOP_100_GEM_FILENAME)) do |gem_name|
      directory = File.expand_path("#{TOP_100_GEMS_DIR}/#{gem_name}")
      next if File.directory?(directory)

      puts "Downloading #{gem_name}"

      uri = URI.parse("https://rubygems.org/gems/#{gem_name}.gem")
      response = Net::HTTP.get_response(uri)
      raise gem_name unless response.is_a?(Net::HTTPSuccess)

      Dir.mktmpdir do |tmpdir|
        filepath = File.join(tmpdir, "#{gem_name}.gem")
        File.write(filepath, response.body)
        Gem::Package.new(filepath).extract_files(directory, "**/*.rb")
      end
    end
  end
end

# This task indexes against the top 100 gems, and will exit(1) if any fail.
desc "Index against the top 100 rubygems"
task "index:topgems": ["download:topgems"] do
  $LOAD_PATH.unshift(File.expand_path("../lib", __dir__))
  require "net/http"
  require "rubygems/package"
  require "tmpdir"

  gem_names = YAML.safe_load_file(TOP_100_GEM_FILENAME)

  errors = []
  GemIndexing.parallelize(gem_names) do |gem_name|
    directory = File.expand_path("#{TOP_100_GEMS_DIR}/#{gem_name}")

    index = RubyIndexer::Index.new

    errors = Dir[File.join(directory, "**", "*.rb")].filter_map do |filepath|
      print(".")
      code = File.read(filepath)
      index.index_single(URI::Generic.from_path(path: filepath), code)
      nil
    rescue => e
      errors << { message: e.message, file: filepath }
    end
  end

  puts "errors: #{errors}" if errors.any?
ensure
  FileUtils.rm_rf(TOP_100_GEMS_DIR)
end
