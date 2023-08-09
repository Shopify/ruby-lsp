# typed: strict
# frozen_string_literal: true

module RubyIndexer
  class Configuration
    extend T::Sig

    sig { void }
    def initialize
      development_only_dependencies = Bundler.definition.dependencies.filter_map do |dependency|
        dependency.name if dependency.groups == [:development]
      end

      @excluded_gems = T.let(development_only_dependencies, T::Array[String])
      @included_gems = T.let([], T::Array[String])
      @excluded_patterns = T.let(["*_test.rb"], T::Array[String])
      @included_patterns = T.let(["#{Dir.pwd}/**/*.rb"], T::Array[String])
    end

    sig { params(config: T::Hash[String, T.untyped]).void }
    def apply_config(config)
      excluded_gems = config.delete("excluded_gems")
      @excluded_gems.concat(excluded_gems) if excluded_gems

      included_gems = config.delete("included_gems")
      @included_gems.concat(included_gems) if included_gems

      excluded_patterns = config.delete("excluded_patterns")
      @excluded_patterns.concat(excluded_patterns) if excluded_patterns

      included_patterns = config.delete("included_patterns")
      @included_patterns.concat(included_patterns) if included_patterns

      raise ArgumentError, "Unknown configuration options: #{config.keys.join(", ")}" if config.any?
    end

    sig { returns(T::Array[String]) }
    def files_to_index
      files_to_index = $LOAD_PATH.flat_map { |p| Dir.glob("#{p}/**/*.rb", base: p) }

      @included_patterns.each do |pattern|
        files_to_index.concat(Dir.glob(pattern, File::FNM_PATHNAME | File::FNM_EXTGLOB))
      end

      excluded_gem_paths = (@excluded_gems - @included_gems).filter_map do |gem_name|
        Gem::Specification.find_by_name(gem_name).full_gem_path
      rescue Gem::MissingSpecError
        warn("Gem #{gem_name} is excluded in .index.yml, but that gem was not found in the bundle")
      end

      files_to_index.reject! do |path|
        @excluded_patterns.any? { |pattern| File.fnmatch?(pattern, path, File::FNM_PATHNAME | File::FNM_EXTGLOB) } ||
          excluded_gem_paths.any? { |gem_path| File.fnmatch?("#{gem_path}/**/*.rb", path) }
      end
      files_to_index.uniq!
      files_to_index
    end
  end
end
