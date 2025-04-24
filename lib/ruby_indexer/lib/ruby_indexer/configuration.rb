# typed: strict
# frozen_string_literal: true

module RubyIndexer
  class Configuration
    CONFIGURATION_SCHEMA = {
      "excluded_gems" => Array,
      "included_gems" => Array,
      "excluded_patterns" => Array,
      "included_patterns" => Array,
      "excluded_magic_comments" => Array,
    }.freeze #: Hash[String, untyped]

    #: String
    attr_writer :workspace_path

    #: Encoding
    attr_accessor :encoding

    #: -> void
    def initialize
      @workspace_path = Dir.pwd #: String
      @encoding = Encoding::UTF_8 #: Encoding
      @excluded_gems = initial_excluded_gems #: Array[String]
      @included_gems = [] #: Array[String]

      @excluded_patterns = [
        "**/{test,spec}/**/{*_test.rb,test_*.rb,*_spec.rb}",
        "**/fixtures/**/*",
      ] #: Array[String]

      path = Bundler.settings["path"]
      if path
        # Substitute Windows backslashes into forward slashes, which are used in glob patterns
        glob = path.gsub(/[\\]+/, "/")
        glob.delete_suffix!("/")
        @excluded_patterns << "#{glob}/**/*.rb"
      end

      # We start the included patterns with only the non excluded directories so that we can avoid paying the price of
      # traversing large directories that don't include Ruby files like `node_modules`
      @included_patterns = ["{#{top_level_directories.join(",")}}/**/*.rb", "*.rb"] #: Array[String]
      @excluded_magic_comments = [
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
      ] #: Array[String]
    end

    #: -> Array[URI::Generic]
    def indexable_uris
      excluded_gems = @excluded_gems - @included_gems
      locked_gems = Bundler.locked_gems&.specs

      # NOTE: indexing the patterns (both included and excluded) needs to happen before indexing gems, otherwise we risk
      # having duplicates if BUNDLE_PATH is set to a folder inside the project structure

      flags = File::FNM_PATHNAME | File::FNM_EXTGLOB

      uris = @included_patterns.flat_map do |pattern|
        load_path_entry = T.let(nil, T.nilable(String))

        Dir.glob(File.join(@workspace_path, pattern), flags).map! do |path|
          # All entries for the same pattern match the same $LOAD_PATH entry. Since searching the $LOAD_PATH for every
          # entry is expensive, we memoize it until we find a path that doesn't belong to that $LOAD_PATH. This happens
          # on repositories that define multiple gems, like Rails. All frameworks are defined inside the current
          # workspace directory, but each one of them belongs to a different $LOAD_PATH entry
          if load_path_entry.nil? || !path.start_with?(load_path_entry)
            load_path_entry = $LOAD_PATH.find { |load_path| path.start_with?(load_path) }
          end

          URI::Generic.from_path(path: path, load_path_entry: load_path_entry)
        end
      end

      # If the patterns are relative, we make it relative to the workspace path. If they are absolute, then we shouldn't
      # concatenate anything
      excluded_patterns = @excluded_patterns.map do |pattern|
        if File.absolute_path?(pattern)
          pattern
        else
          File.join(@workspace_path, pattern)
        end
      end

      # Remove user specified patterns
      bundle_path = Bundler.settings["path"]&.gsub(/[\\]+/, "/")
      uris.reject! do |indexable|
        path = indexable.full_path #: as !nil
        next false if test_files_ignored_from_exclusion?(path, bundle_path)

        excluded_patterns.any? { |pattern| File.fnmatch?(pattern, path, flags) }
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
          uris.concat(
            Dir.glob(File.join(default_path, "**", "*.rb"), File::FNM_PATHNAME | File::FNM_EXTGLOB).map! do |path|
              URI::Generic.from_path(path: path, load_path_entry: RbConfig::CONFIG["rubylibdir"])
            end,
          )
        elsif pathname.extname == ".rb"
          # If the default_path is a Ruby file, we index it
          uris << URI::Generic.from_path(path: default_path, load_path_entry: RbConfig::CONFIG["rubylibdir"])
        end
      end

      # Add the locked gems to the list of files to be indexed
      locked_gems&.each do |lazy_spec|
        next if excluded_gems.include?(lazy_spec.name)

        spec = Gem::Specification.find_by_name(lazy_spec.name)

        # When working on a gem, it will be included in the locked_gems list. Since these are the project's own files,
        # we have already included and handled exclude patterns for it and should not re-include or it'll lead to
        # duplicates or accidentally ignoring exclude patterns
        next if spec.full_gem_path == @workspace_path

        uris.concat(
          spec.require_paths.flat_map do |require_path|
            load_path_entry = File.join(spec.full_gem_path, require_path)
            Dir.glob(File.join(load_path_entry, "**", "*.rb")).map! do |path|
              URI::Generic.from_path(path: path, load_path_entry: load_path_entry)
            end
          end,
        )
      rescue Gem::MissingSpecError
        # If a gem is scoped only to some specific platform, then its dependencies may not be installed either, but they
        # are still listed in locked_gems. We can't index them because they are not installed for the platform, so we
        # just ignore if they're missing
      end

      uris.uniq!(&:to_s)
      uris
    end

    #: -> Regexp
    def magic_comment_regex
      @magic_comment_regex ||= /^#\s*#{@excluded_magic_comments.join("|")}/ #: Regexp?
    end

    #: (Hash[String, untyped] config) -> void
    def apply_config(config)
      validate_config!(config)

      @excluded_gems.concat(config["excluded_gems"]) if config["excluded_gems"]
      @included_gems.concat(config["included_gems"]) if config["included_gems"]
      @excluded_patterns.concat(config["excluded_patterns"]) if config["excluded_patterns"]
      @included_patterns.concat(config["included_patterns"]) if config["included_patterns"]
      @excluded_magic_comments.concat(config["excluded_magic_comments"]) if config["excluded_magic_comments"]
    end

    private

    #: (Hash[String, untyped] config) -> void
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

    #: -> Array[String]
    def initial_excluded_gems
      excluded, others = Bundler.definition.dependencies.partition do |dependency|
        dependency.groups == [:development]
      end

      # When working on a gem, we need to make sure that its gemspec dependencies can't be excluded. This is necessary
      # because Bundler doesn't assign groups to gemspec dependencies
      #
      # If the dependency is prerelease, `to_spec` may return `nil` due to a bug in older version of Bundler/RubyGems:
      # https://github.com/Shopify/ruby-lsp/issues/1246
      this_gem = Bundler.definition.dependencies.find do |d|
        d.to_spec&.full_gem_path == @workspace_path
      rescue Gem::MissingSpecError
        false
      end

      others.concat(this_gem.to_spec.dependencies) if this_gem
      others.concat(
        others.filter_map do |d|
          d.to_spec&.dependencies
        rescue Gem::MissingSpecError
          nil
        end.flatten,
      )
      others.uniq!
      others.map!(&:name)

      excluded.each do |dependency|
        next unless dependency.runtime?

        spec = dependency.to_spec
        next unless spec

        spec.dependencies.each do |transitive_dependency|
          next if others.include?(transitive_dependency.name)

          excluded << transitive_dependency
        end
      rescue Gem::MissingSpecError
        # If a gem is scoped only to some specific platform, then its dependencies may not be installed either, but they
        # are still listed in dependencies. We can't index them because they are not installed for the platform, so we
        # just ignore if they're missing
      end

      excluded.uniq!
      excluded.map(&:name)
    rescue Bundler::GemfileNotFound
      []
    end

    # Checks if the test file is never supposed to be ignored from indexing despite matching exclusion patterns, like
    # `test_helper.rb` or `test_case.rb`. Also takes into consideration the possibility of finding these files under
    # fixtures or inside gem source code if the bundle path points to a directory inside the workspace
    #: (String path, String? bundle_path) -> bool
    def test_files_ignored_from_exclusion?(path, bundle_path)
      ["test_case.rb", "test_helper.rb"].include?(File.basename(path)) &&
        !File.fnmatch?("**/fixtures/**/*", path, File::FNM_PATHNAME | File::FNM_EXTGLOB) &&
        (!bundle_path || !path.start_with?(bundle_path))
    end

    #: -> Array[String]
    def top_level_directories
      excluded_directories = ["tmp", "node_modules", "sorbet"]

      Dir.glob("#{Dir.pwd}/*").filter_map do |path|
        dir_name = File.basename(path)
        next unless File.directory?(path) && !excluded_directories.include?(dir_name)

        dir_name
      end
    end
  end
end
