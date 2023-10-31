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
      @excluded_gems = T.let(initial_excluded_gems, T::Array[String])
      @included_gems = T.let([], T::Array[String])
      @excluded_patterns = T.let([File.join("**", "*_test.rb")], T::Array[String])
      path = Bundler.settings["path"]
      @excluded_patterns << File.join(File.expand_path(path, Dir.pwd), "**", "*.rb") if path

      @included_patterns = T.let([File.join(Dir.pwd, "**", "*.rb")], T::Array[String])
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

    sig { returns(T::Array[IndexablePath]) }
    def indexables
      excluded_gems = @excluded_gems - @included_gems
      locked_gems = Bundler.locked_gems&.specs

      # NOTE: indexing the patterns (both included and excluded) needs to happen before indexing gems, otherwise we risk
      # having duplicates if BUNDLE_PATH is set to a folder inside the project structure

      # Add user specified patterns
      indexables = @included_patterns.flat_map do |pattern|
        load_path_entry = T.let(nil, T.nilable(String))

        Dir.glob(pattern, File::FNM_PATHNAME | File::FNM_EXTGLOB).map! do |path|
          # All entries for the same pattern match the same $LOAD_PATH entry. Since searching the $LOAD_PATH for every
          # entry is expensive, we memoize it for the entire pattern
          load_path_entry ||= $LOAD_PATH.find { |load_path| path.start_with?(load_path) }
          IndexablePath.new(load_path_entry, path)
        end
      end

      # Remove user specified patterns
      indexables.reject! do |indexable|
        @excluded_patterns.any? do |pattern|
          File.fnmatch?(pattern, indexable.full_path, File::FNM_PATHNAME | File::FNM_EXTGLOB)
        end
      end

      # Add default gems to the list of files to be indexed
      Dir.glob(File.join(RbConfig::CONFIG["rubylibdir"], "*")).each do |default_path|
        # The default_path might be a Ruby file or a folder with the gem's name. For example:
        #   bundler/
        #   bundler.rb
        #   psych/
        #   psych.rb
        pathname = Pathname.new(default_path)
        short_name = pathname.basename.to_s.delete_suffix(".rb")

        # If the gem name is excluded, then we skip it
        next if excluded_gems.include?(short_name)

        # If the default gem is also a part of the bundle, we skip indexing the default one and index only the one in
        # the bundle, which won't be in `default_path`, but will be in `Bundler.bundle_path` instead
        next if locked_gems&.any? do |locked_spec|
          locked_spec.name == short_name &&
            !Gem::Specification.find_by_name(short_name).full_gem_path.start_with?(RbConfig::CONFIG["rubylibprefix"])
        rescue Gem::MissingSpecError
          # If a default gem is scoped to a specific platform, then `find_by_name` will raise. We want to skip those
          # cases
          true
        end

        if pathname.directory?
          # If the default_path is a directory, we index all the Ruby files in it
          indexables.concat(
            Dir.glob(File.join(default_path, "**", "*.rb"), File::FNM_PATHNAME | File::FNM_EXTGLOB).map! do |path|
              IndexablePath.new(RbConfig::CONFIG["rubylibdir"], path)
            end,
          )
        else
          # If the default_path is a Ruby file, we index it
          indexables << IndexablePath.new(RbConfig::CONFIG["rubylibdir"], default_path)
        end
      end

      # Add the locked gems to the list of files to be indexed
      locked_gems&.each do |lazy_spec|
        next if excluded_gems.include?(lazy_spec.name)

        spec = Gem::Specification.find_by_name(lazy_spec.name)

        # When working on a gem, it will be included in the locked_gems list. Since these are the project's own files,
        # we have already included and handled exclude patterns for it and should not re-include or it'll lead to
        # duplicates or accidentally ignoring exclude patterns
        next if spec.full_gem_path == Dir.pwd

        indexables.concat(
          spec.require_paths.flat_map do |require_path|
            load_path_entry = File.join(spec.full_gem_path, require_path)
            Dir.glob(File.join(load_path_entry, "**", "*.rb")).map! { |path| IndexablePath.new(load_path_entry, path) }
          end,
        )
      rescue Gem::MissingSpecError
        # If a gem is scoped only to some specific platform, then its dependencies may not be installed either, but they
        # are still listed in locked_gems. We can't index them because they are not installed for the platform, so we
        # just ignore if they're missing
      end

      indexables.uniq!
      indexables
    end

    sig { returns(Regexp) }
    def magic_comment_regex
      @magic_comment_regex ||= T.let(/^#\s*#{@excluded_magic_comments.join("|")}/, T.nilable(Regexp))
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

    sig { returns(T::Array[String]) }
    def initial_excluded_gems
      excluded, others = Bundler.definition.dependencies.partition do |dependency|
        dependency.groups == [:development]
      end

      # When working on a gem, we need to make sure that its gemspec dependencies can't be excluded. This is necessary
      # because Bundler doesn't assign groups to gemspec dependencies
      this_gem = Bundler.definition.dependencies.find do |d|
        d.to_spec.full_gem_path == Dir.pwd
      rescue Gem::MissingSpecError
        false
      end

      others.concat(this_gem.to_spec.dependencies) if this_gem

      excluded.each do |dependency|
        next unless dependency.runtime?

        # If the dependency is prerelease, to_spec may return `nil`
        spec = dependency.to_spec
        next unless spec

        spec.dependencies.each do |transitive_dependency|
          # If the transitive dependency is included in other groups, skip it
          next if others.any? { |d| d.name == transitive_dependency.name }

          # If the transitive dependency is included as a transitive dependency of a gem outside of the development
          # group, skip it
          next if others.any? { |d| d.to_spec.dependencies.include?(transitive_dependency) }

          excluded << transitive_dependency
        end
      rescue Gem::MissingSpecError
        # If a gem is scoped only to some specific platform, then its dependencies may not be installed either, but they
        # are still listed in dependencies. We can't index them because they are not installed for the platform, so we
        # just ignore if they're missing
      end

      excluded.uniq!
      excluded.map(&:name)
    end
  end
end
