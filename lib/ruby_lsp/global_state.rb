# typed: strict
# frozen_string_literal: true

module RubyLsp
  class GlobalState
    extend T::Sig

    sig { returns(String) }
    attr_reader :test_library

    sig { returns(String) }
    attr_accessor :formatter

    sig { returns(T::Boolean) }
    attr_reader :has_type_checker

    sig { returns(RubyIndexer::Index) }
    attr_reader :index

    sig { returns(Encoding) }
    attr_reader :encoding

    sig { returns(T::Boolean) }
    attr_reader :top_level_bundle

    sig { returns(TypeInferrer) }
    attr_reader :type_inferrer

    sig { returns(ClientCapabilities) }
    attr_reader :client_capabilities

    sig { returns(URI::Generic) }
    attr_reader :workspace_uri

    sig { void }
    def initialize
      @workspace_uri = T.let(URI::Generic.from_path(path: Dir.pwd), URI::Generic)
      @encoding = T.let(Encoding::UTF_8, Encoding)

      @formatter = T.let("auto", String)
      @linters = T.let([], T::Array[String])
      @test_library = T.let("minitest", String)
      @has_type_checker = T.let(true, T::Boolean)
      @index = T.let(RubyIndexer::Index.new, RubyIndexer::Index)
      @supported_formatters = T.let({}, T::Hash[String, Requests::Support::Formatter])
      @type_inferrer = T.let(TypeInferrer.new(@index), TypeInferrer)
      @addon_settings = T.let({}, T::Hash[String, T.untyped])
      @top_level_bundle = T.let(
        begin
          Bundler.with_original_env { Bundler.default_gemfile }
          true
        rescue Bundler::GemfileNotFound, Bundler::GitError
          false
        end,
        T::Boolean,
      )
      @client_capabilities = T.let(ClientCapabilities.new, ClientCapabilities)
      @enabled_feature_flags = T.let({}, T::Hash[Symbol, T::Boolean])
      @mutex = T.let(Mutex.new, Mutex)
    end

    sig { type_parameters(:T).params(block: T.proc.returns(T.type_parameter(:T))).returns(T.type_parameter(:T)) }
    def synchronize(&block)
      @mutex.synchronize(&block)
    end

    sig { params(addon_name: String).returns(T.nilable(T::Hash[Symbol, T.untyped])) }
    def settings_for_addon(addon_name)
      @addon_settings[addon_name]
    end

    sig { params(identifier: String, instance: Requests::Support::Formatter).void }
    def register_formatter(identifier, instance)
      @supported_formatters[identifier] = instance
    end

    sig { returns(T.nilable(Requests::Support::Formatter)) }
    def active_formatter
      @supported_formatters[@formatter]
    end

    sig { returns(T::Array[Requests::Support::Formatter]) }
    def active_linters
      @linters.filter_map { |name| @supported_formatters[name] }
    end

    # Applies the options provided by the editor and returns an array of notifications to send back to the client
    sig { params(options: T::Hash[Symbol, T.untyped]).returns(T::Array[Notification]) }
    def apply_options(options)
      notifications = []
      direct_dependencies = gather_direct_dependencies
      all_dependencies = gather_direct_and_indirect_dependencies
      workspace_uri = options.dig(:workspaceFolders, 0, :uri)
      @workspace_uri = URI(workspace_uri) if workspace_uri

      specified_formatter = options.dig(:initializationOptions, :formatter)
      rubocop_has_addon = defined?(::RuboCop::Version::STRING) &&
        Gem::Requirement.new(">= 1.70.0").satisfied_by?(Gem::Version.new(::RuboCop::Version::STRING))

      if specified_formatter
        @formatter = specified_formatter

        if specified_formatter != "auto"
          notifications << Notification.window_log_message("Using formatter specified by user: #{@formatter}")
        end

        # If the user had originally configured to use `rubocop`, but their version doesn't provide the add-on yet,
        # fallback to the internal integration
        if specified_formatter == "rubocop" && !rubocop_has_addon
          @formatter = "rubocop_internal"
        end
      end

      if @formatter == "auto"
        @formatter = detect_formatter(direct_dependencies, all_dependencies)
        notifications << Notification.window_log_message("Auto detected formatter: #{@formatter}")
      end

      specified_linters = options.dig(:initializationOptions, :linters)

      if specified_formatter == "rubocop" || specified_linters&.include?("rubocop")
        notifications << Notification.window_log_message(<<~MESSAGE, type: Constant::MessageType::WARNING)
          Formatter is configured to be `rubocop`. As of RuboCop v1.70.0, this identifier activates the add-on
          implemented in the rubocop gem itself instead of the internal integration provided by the Ruby LSP.

          If you wish to use the internal integration, please configure the formatter as `rubocop_internal`.
        MESSAGE
      end

      # If the user had originally configured to use `rubocop`, but their version doesn't provide the add-on yet,
      # fall back to the internal integration
      if specified_linters&.include?("rubocop") && !rubocop_has_addon
        specified_linters.delete("rubocop")
        specified_linters << "rubocop_internal"
      end

      @linters = specified_linters || detect_linters(direct_dependencies, all_dependencies)

      notifications << if specified_linters
        Notification.window_log_message("Using linters specified by user: #{@linters.join(", ")}")
      else
        Notification.window_log_message("Auto detected linters: #{@linters.join(", ")}")
      end

      @test_library = detect_test_library(direct_dependencies)
      notifications << Notification.window_log_message("Detected test library: #{@test_library}")

      @has_type_checker = detect_typechecker(all_dependencies)
      if @has_type_checker
        notifications << Notification.window_log_message(
          "Ruby LSP detected this is a Sorbet project and will defer to the Sorbet LSP for some functionality",
        )
      end

      encodings = options.dig(:capabilities, :general, :positionEncodings)
      @encoding = if !encodings || encodings.empty?
        Encoding::UTF_16LE
      elsif encodings.include?(Constant::PositionEncodingKind::UTF8)
        Encoding::UTF_8
      elsif encodings.include?(Constant::PositionEncodingKind::UTF16)
        Encoding::UTF_16LE
      else
        Encoding::UTF_32
      end
      @index.configuration.encoding = @encoding

      @client_capabilities.apply_client_capabilities(options[:capabilities]) if options[:capabilities]

      addon_settings = options.dig(:initializationOptions, :addonSettings)
      if addon_settings
        addon_settings.transform_keys!(&:to_s)
        @addon_settings.merge!(addon_settings)
      end

      enabled_flags = options.dig(:initializationOptions, :enabledFeatureFlags)
      @enabled_feature_flags = enabled_flags if enabled_flags

      notifications
    end

    sig { params(flag: Symbol).returns(T.nilable(T::Boolean)) }
    def enabled_feature?(flag)
      @enabled_feature_flags[:all] || @enabled_feature_flags[flag]
    end

    sig { returns(String) }
    def workspace_path
      T.must(@workspace_uri.to_standardized_path)
    end

    sig { returns(String) }
    def encoding_name
      case @encoding
      when Encoding::UTF_8
        Constant::PositionEncodingKind::UTF8
      when Encoding::UTF_16LE
        Constant::PositionEncodingKind::UTF16
      else
        Constant::PositionEncodingKind::UTF32
      end
    end

    sig { returns(T::Boolean) }
    def supports_watching_files
      @client_capabilities.supports_watching_files
    end

    private

    sig { params(direct_dependencies: T::Array[String], all_dependencies: T::Array[String]).returns(String) }
    def detect_formatter(direct_dependencies, all_dependencies)
      # NOTE: Intentionally no $ at end, since we want to match rubocop-shopify, etc.
      return "rubocop_internal" if direct_dependencies.any?(/^rubocop/)

      syntax_tree_is_direct_dependency = direct_dependencies.include?("syntax_tree")
      return "syntax_tree" if syntax_tree_is_direct_dependency

      rubocop_is_transitive_dependency = all_dependencies.include?("rubocop")
      return "rubocop_internal" if dot_rubocop_yml_present && rubocop_is_transitive_dependency

      "none"
    end

    # Try to detect if there are linters in the project's dependencies. For auto-detection, we always only consider a
    # single linter. To have multiple linters running, the user must configure them manually
    sig { params(dependencies: T::Array[String], all_dependencies: T::Array[String]).returns(T::Array[String]) }
    def detect_linters(dependencies, all_dependencies)
      linters = []

      if dependencies.any?(/^rubocop/) || (all_dependencies.include?("rubocop") && dot_rubocop_yml_present)
        linters << "rubocop_internal"
      end

      linters
    end

    sig { params(dependencies: T::Array[String]).returns(String) }
    def detect_test_library(dependencies)
      if dependencies.any?(/^rspec/)
        "rspec"
      # A Rails app may have a dependency on minitest, but we would instead want to use the Rails test runner provided
      # by ruby-lsp-rails. A Rails app doesn't need to depend on the rails gem itself, individual components like
      # activestorage may be added to the gemfile so that other components aren't downloaded. Check for the presence
      #  of bin/rails to support these cases.
      elsif bin_rails_present
        "rails"
      # NOTE: Intentionally ends with $ to avoid mis-matching minitest-reporters, etc. in a Rails app.
      elsif dependencies.any?(/^minitest$/)
        "minitest"
      elsif dependencies.any?(/^test-unit/)
        "test-unit"
      else
        "unknown"
      end
    end

    sig { params(dependencies: T::Array[String]).returns(T::Boolean) }
    def detect_typechecker(dependencies)
      return false if ENV["RUBY_LSP_BYPASS_TYPECHECKER"]

      dependencies.any?(/^sorbet-static/)
    rescue Bundler::GemfileNotFound
      false
    end

    sig { returns(T::Boolean) }
    def bin_rails_present
      File.exist?(File.join(workspace_path, "bin/rails"))
    end

    sig { returns(T::Boolean) }
    def dot_rubocop_yml_present
      File.exist?(File.join(workspace_path, ".rubocop.yml"))
    end

    sig { returns(T::Array[String]) }
    def gather_direct_dependencies
      Bundler.with_original_env { Bundler.default_gemfile }

      dependencies = Bundler.locked_gems&.dependencies&.keys || []
      dependencies + gemspec_dependencies
    rescue Bundler::GemfileNotFound
      []
    end

    sig { returns(T::Array[String]) }
    def gemspec_dependencies
      (Bundler.locked_gems&.sources || [])
        .grep(Bundler::Source::Gemspec)
        .flat_map { _1.gemspec&.dependencies&.map(&:name) }
    end

    sig { returns(T::Array[String]) }
    def gather_direct_and_indirect_dependencies
      Bundler.with_original_env { Bundler.default_gemfile }
      Bundler.locked_gems&.specs&.map(&:name) || []
    rescue Bundler::GemfileNotFound
      []
    end
  end
end
