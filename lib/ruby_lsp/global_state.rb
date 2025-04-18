# typed: strict
# frozen_string_literal: true

module RubyLsp
  class GlobalState
    #: String
    attr_reader :test_library

    #: String
    attr_accessor :formatter

    #: bool
    attr_reader :has_type_checker

    #: RubyIndexer::Index
    attr_reader :index

    #: Encoding
    attr_reader :encoding

    #: bool
    attr_reader :top_level_bundle

    #: TypeInferrer
    attr_reader :type_inferrer

    #: ClientCapabilities
    attr_reader :client_capabilities

    #: URI::Generic
    attr_reader :workspace_uri

    #: String?
    attr_reader :telemetry_machine_id

    #: -> void
    def initialize
      @workspace_uri = URI::Generic.from_path(path: Dir.pwd) #: URI::Generic
      @encoding = Encoding::UTF_8 #: Encoding

      @formatter = "auto" #: String
      @linters = [] #: Array[String]
      @test_library = "minitest" #: String
      @has_type_checker = true #: bool
      @index = RubyIndexer::Index.new #: RubyIndexer::Index
      @supported_formatters = {} #: Hash[String, Requests::Support::Formatter]
      @type_inferrer = TypeInferrer.new(@index) #: TypeInferrer
      @addon_settings = {} #: Hash[String, untyped]
      @top_level_bundle = begin
        Bundler.with_original_env { Bundler.default_gemfile }
        true
      rescue Bundler::GemfileNotFound, Bundler::GitError
        false
      end #: bool
      @client_capabilities = ClientCapabilities.new #: ClientCapabilities
      @enabled_feature_flags = {} #: Hash[Symbol, bool]
      @mutex = Mutex.new #: Mutex
      @telemetry_machine_id = nil #: String?
    end

    #: [T] { -> T } -> T
    def synchronize(&block)
      @mutex.synchronize(&block)
    end

    #: (String addon_name) -> Hash[Symbol, untyped]?
    def settings_for_addon(addon_name)
      @addon_settings[addon_name]
    end

    #: (String identifier, Requests::Support::Formatter instance) -> void
    def register_formatter(identifier, instance)
      @supported_formatters[identifier] = instance
    end

    #: -> Requests::Support::Formatter?
    def active_formatter
      @supported_formatters[@formatter]
    end

    #: -> Array[Requests::Support::Formatter]
    def active_linters
      @linters.filter_map { |name| @supported_formatters[name] }
    end

    # Applies the options provided by the editor and returns an array of notifications to send back to the client
    #: (Hash[Symbol, untyped] options) -> Array[Notification]
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

      @telemetry_machine_id = options.dig(:initializationOptions, :telemetryMachineId)
      notifications
    end

    #: (Symbol flag) -> bool?
    def enabled_feature?(flag)
      @enabled_feature_flags[:all] || @enabled_feature_flags[flag]
    end

    #: -> String
    def workspace_path
      @workspace_uri.to_standardized_path #: as !nil
    end

    #: -> String
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

    #: -> bool
    def supports_watching_files
      @client_capabilities.supports_watching_files
    end

    private

    #: (Array[String] direct_dependencies, Array[String] all_dependencies) -> String
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
    #: (Array[String] dependencies, Array[String] all_dependencies) -> Array[String]
    def detect_linters(dependencies, all_dependencies)
      linters = []

      if dependencies.any?(/^rubocop/) || (all_dependencies.include?("rubocop") && dot_rubocop_yml_present)
        linters << "rubocop_internal"
      end

      linters
    end

    #: (Array[String] dependencies) -> String
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

    #: (Array[String] dependencies) -> bool
    def detect_typechecker(dependencies)
      return false if ENV["RUBY_LSP_BYPASS_TYPECHECKER"]

      dependencies.any?(/^sorbet-static/)
    rescue Bundler::GemfileNotFound
      false
    end

    #: -> bool
    def bin_rails_present
      File.exist?(File.join(workspace_path, "bin/rails"))
    end

    #: -> bool
    def dot_rubocop_yml_present
      File.exist?(File.join(workspace_path, ".rubocop.yml"))
    end

    #: -> Array[String]
    def gather_direct_dependencies
      Bundler.with_original_env { Bundler.default_gemfile }

      dependencies = Bundler.locked_gems&.dependencies&.keys || []
      dependencies + gemspec_dependencies
    rescue Bundler::GemfileNotFound
      []
    end

    #: -> Array[String]
    def gemspec_dependencies
      (Bundler.locked_gems&.sources || [])
        .grep(Bundler::Source::Gemspec)
        .flat_map { _1.gemspec&.dependencies&.map(&:name) }
    end

    #: -> Array[String]
    def gather_direct_and_indirect_dependencies
      Bundler.with_original_env { Bundler.default_gemfile }
      Bundler.locked_gems&.specs&.map(&:name) || []
    rescue Bundler::GemfileNotFound
      []
    end
  end
end
