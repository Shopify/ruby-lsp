# typed: strict
# frozen_string_literal: true

module RubyIndexer
  class Configuration
    extend T::Sig

    CONFIGURATION_SCHEMA = T.let(
      {
        "excluded_gems" => Array,
        "included_gems" => Array,
        "excluded_patterns" => Array,
        "included_patterns" => Array,
        "excluded_magic_comments" => Array,
      }.freeze,
      T::Hash[String, T.untyped],
    )

    sig { void }
    def initialize
      development_only_dependencies = Bundler.definition.dependencies.filter_map do |dependency|
        dependency.name if dependency.groups == [:development]
      end

      @excluded_gems = T.let(development_only_dependencies, T::Array[String])
      @included_gems = T.let([], T::Array[String])
      @excluded_patterns = T.let(["*_test.rb"], T::Array[String])
      @included_patterns = T.let(["#{Dir.pwd}/**/*.rb"], T::Array[String])
      @excluded_magic_comments = T.let(
        [
          "frozen_string_literal:",
          "typed:",
          "compiled:",
          "encoding:",
          "shareable_constant_value:",
          "warn_indent:",
          "rubocop:",
          "nodoc:",
          "doc:",
          "coding:",
          "warn_past_scope:",
        ],
        T::Array[String],
      )
    end

    sig { void }
    def load_config
      return unless File.exist?(".index.yml")

      config = YAML.parse_file(".index.yml")
      return unless config

      config_hash = config.to_ruby
      validate_config!(config_hash)
      apply_config(config_hash)
    rescue Psych::SyntaxError => e
      raise e, "Syntax error while loading .index.yml configuration: #{e.message}"
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

    sig { returns(Regexp) }
    def magic_comment_regex
      /^\s*#\s*#{@excluded_magic_comments.join("|")}/
    end

    private

    sig { params(config: T::Hash[String, T.untyped]).void }
    def validate_config!(config)
      errors = config.filter_map do |key, value|
        type = CONFIGURATION_SCHEMA[key]

        if type.nil?
          "Unknown configuration option: #{key}"
        elsif !value.is_a?(type)
          "Expected #{key} to be a #{type}, but got #{value.class}"
        end
      end

      raise ArgumentError, errors.join("\n") if errors.any?
    end

    sig { params(config: T::Hash[String, T.untyped]).void }
    def apply_config(config)
      @excluded_gems.concat(config["excluded_gems"]) if config["excluded_gems"]
      @included_gems.concat(config["included_gems"]) if config["included_gems"]
      @excluded_patterns.concat(config["excluded_patterns"]) if config["excluded_patterns"]
      @included_patterns.concat(config["included_patterns"]) if config["included_patterns"]
      @excluded_magic_comments.concat(config["excluded_magic_comments"]) if config["excluded_magic_comments"]
    end
  end
end
