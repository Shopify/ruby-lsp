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

    sig { params(workspace_path: String).void }
    attr_writer :workspace_path

    sig { returns(Encoding) }
    attr_accessor :encoding

    sig { void }
    def initialize
      @workspace_path = T.let(Dir.pwd, String)
      @encoding = T.let(Encoding::UTF_8, Encoding)
      @excluded_gems = T.let(initial_excluded_gems, T::Array[String])
      @included_gems = T.let([], T::Array[String])

      @excluded_patterns = T.let(
        [
          File.join("**", "*_test.rb"),
          File.join("node_modules", "**", "*"),
          File.join("spec", "**", "*"),
          File.join("test", "**", "*"),
          File.join("tmp", "**", "*"),
        ],
        T::Array[String],
      )

      path = Bundler.settings["path"]
      if path
        # Substitute Windows backslashes into forward slashes, which are used in glob patterns
        glob = path.gsub(/[\\]+/, "/")
        @excluded_patterns << File.join(glob, "**", "*.rb")
      end

      @included_patterns = T.let([File.join("**", "*.rb")], T::Array[String])
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

    sig { returns(String) }
    def merged_excluded_file_pattern
      # This regex looks for @excluded_patterns that follow the format of "something/**/*", where
      # "something" is one or more non-"/"
      #
      # Returns "/path/to/workspace/{tmp,node_modules}/**/*"
      @excluded_patterns
        .filter_map do |pattern|
          next if File.absolute_path?(pattern)

          pattern.match(%r{\A([^/]+)/\*\*/\*\z})&.captures&.first
        end
        .then { |dirs| File.join(@workspace_path, "{#{dirs.join(",")}}/**/*") }
    end

    sig { returns(T::Array[URI::Generic]) }
    def indexable_uris
      excluded_gems = @excluded_gems - @included_gems
      locked_gems = Bundler.locked_gems&.specs

      # NOTE: indexing the patterns (both included and excluded) needs to happen before indexing gems, otherwise we risk
      # having duplicates if BUNDLE_PATH is set to a folder inside the project structure

      flags = File::FNM_PATHNAME | File::FNM_EXTGLOB

      # In order to speed up indexing, only traverse into top-level directories that are not entirely excluded.
      # For example, if "tmp/**/*" is excluded, we don't need to traverse into "tmp" at all. However, if
      # "vendor/bundle/**/*" is excluded, we will traverse all of "vendor" and `reject!` out all "vendor/bundle" entries
      # later.
      excluded_pattern = merged_excluded_file_pattern
      included_paths = Dir.glob(File.join(@workspace_path, "*/"), flags)
        .filter_map do |included_path|
          next if File.fnmatch?(excluded_pattern, included_path, flags)

          relative_path = included_path
            .delete_prefix(@workspace_path)
            .tap { |path| path.delete_prefix!("/") }

          [included_path, relative_path]
        end

      uris = T.let([], T::Array[URI::Generic])

      # Handle top level files separately. The path below is an optimization to prevent descending down directories that
      # are going to be excluded anyway, so we need to handle top level scripts separately
      Dir.glob(File.join(@workspace_path, "*.rb"), flags).each do |path|
        uris << URI::Generic.from_path(path: path)
      end

      # Add user specified patterns
      @included_patterns.each do |pattern|
        load_path_entry = T.let(nil, T.nilable(String))

        included_paths.each do |included_path, relative_path|
          relative_pattern = pattern.delete_prefix(File.join(relative_path, "/"))

          next unless pattern.start_with?("**") || pattern.start_with?(relative_path)

          Dir.glob(File.join(included_path, relative_pattern), flags).each do |path|
            path = File.expand_path(path)
            # All entries for the same pattern match the same $LOAD_PATH entry. Since searching the $LOAD_PATH for every
            # entry is expensive, we memoize it until we find a path that doesn't belong to that $LOAD_PATH. This
            # happens on repositories that define multiple gems, like Rails. All frameworks are defined inside the
            # current workspace directory, but each one of them belongs to a different $LOAD_PATH entry
            if load_path_entry.nil? || !path.start_with?(load_path_entry)
              load_path_entry = $LOAD_PATH.find { |load_path| path.start_with?(load_path) }
            end

            uris << URI::Generic.from_path(path: path, load_path_entry: load_path_entry)
          end
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
      uris.reject! do |indexable|
        excluded_patterns.any? do |pattern|
          File.fnmatch?(pattern, T.must(indexable.full_path), File::FNM_PATHNAME | File::FNM_EXTGLOB)
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

    sig { returns(Regexp) }
    def magic_comment_regex
      @magic_comment_regex ||= T.let(/^#\s*#{@excluded_magic_comments.join("|")}/, T.nilable(Regexp))
    end

    sig { params(config: T::Hash[String, T.untyped]).void }
    def apply_config(config)
      validate_config!(config)

      @excluded_gems.concat(config["excluded_gems"]) if config["excluded_gems"]
      @included_gems.concat(config["included_gems"]) if config["included_gems"]
      @excluded_patterns.concat(config["excluded_patterns"]) if config["excluded_patterns"]
      @included_patterns.concat(config["included_patterns"]) if config["included_patterns"]
      @excluded_magic_comments.concat(config["excluded_magic_comments"]) if config["excluded_magic_comments"]
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

    sig { returns(T::Array[String]) }
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
  end
end
