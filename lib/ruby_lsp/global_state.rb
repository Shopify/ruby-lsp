# typed: strict
# frozen_string_literal: true

module RubyLsp
  # Holds the detected value and the reason for detection
  class DetectionResult
    #: String
    attr_reader :value

    #: String
    attr_reader :reason

    #: (String value, String reason) -> void
    def initialize(value, reason)
      @value = value
      @reason = reason
    end
  end

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
      @feature_configuration = {
        inlayHint: RequestConfig.new({
          enableAll: false,
          implicitRescue: false,
          implicitHashValue: false,
        }),
        codeLens: RequestConfig.new({
          enableAll: false,
          enableTestCodeLens: true,
        }),
      } #: Hash[Symbol, RequestConfig]
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
        formatter_result = detect_formatter(direct_dependencies, all_dependencies)
        @formatter = formatter_result.value
        notifications << Notification.window_log_message(
          "Auto detected formatter: #{@formatter} (#{formatter_result.reason})",
        )
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

      if specified_linters
        @linters = specified_linters
        notifications << Notification.window_log_message("Using linters specified by user: #{@linters.join(", ")}")
      else
        linter_results = detect_linters(direct_dependencies, all_dependencies)
        @linters = linter_results.map(&:value)
        linter_messages = linter_results.map { |r| "#{r.value} (#{r.reason})" }
        notifications << Notification.window_log_message("Auto detected linters: #{linter_messages.join(", ")}")
      end

      test_library_result = detect_test_library(direct_dependencies)
      @test_library = test_library_result.value
      notifications << Notification.window_log_message(
        "Detected test library: #{@test_library} (#{test_library_result.reason})",
      )

      typechecker_result = detect_typechecker(all_dependencies)
      @has_type_checker = !typechecker_result.nil?
      if typechecker_result
        notifications << Notification.window_log_message(
          "Ruby LSP detected this is a Sorbet project (#{typechecker_result.reason}) and will defer to the " \
            "Sorbet LSP for some functionality",
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

      options.dig(:initializationOptions, :featuresConfiguration)&.each do |feature_name, config|
        @feature_configuration[feature_name]&.merge!(config)
      end

      notifications
    end

    #: (Symbol) -> RequestConfig?
    def feature_configuration(feature_name)
      @feature_configuration[feature_name]
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

    #: (Array[String] direct_dependencies, Array[String] all_dependencies) -> DetectionResult
    def detect_formatter(direct_dependencies, all_dependencies)
      # NOTE: Intentionally no $ at end, since we want to match rubocop-shopify, etc.
      if direct_dependencies.any?(/^rubocop/)
        return DetectionResult.new("rubocop_internal", "direct dependency matching /^rubocop/")
      end

      if direct_dependencies.include?("syntax_tree")
        return DetectionResult.new("syntax_tree", "direct dependency")
      end

      if all_dependencies.include?("rubocop") && dot_rubocop_yml_present
        return DetectionResult.new("rubocop_internal", "transitive dependency with .rubocop.yml present")
      end

      DetectionResult.new("none", "no formatter detected")
    end

    # Try to detect if there are linters in the project's dependencies. For auto-detection, we always only consider a
    # single linter. To have multiple linters running, the user must configure them manually
    #: (Array[String] dependencies, Array[String] all_dependencies) -> Array[DetectionResult]
    def detect_linters(dependencies, all_dependencies)
      linters = [] #: Array[DetectionResult]

      if dependencies.any?(/^rubocop/)
        linters << DetectionResult.new("rubocop_internal", "direct dependency matching /^rubocop/")
      elsif all_dependencies.include?("rubocop") && dot_rubocop_yml_present
        linters << DetectionResult.new("rubocop_internal", "transitive dependency with .rubocop.yml present")
      end

      linters
    end

    #: (Array[String] dependencies) -> DetectionResult
    def detect_test_library(dependencies)
      if dependencies.any?(/^rspec/)
        DetectionResult.new("rspec", "direct dependency matching /^rspec/")
      # A Rails app may have a dependency on minitest, but we would instead want to use the Rails test runner provided
      # by ruby-lsp-rails. A Rails app doesn't need to depend on the rails gem itself, individual components like
      # activestorage may be added to the gemfile so that other components aren't downloaded. Check for the presence
      #  of bin/rails to support these cases.
      elsif bin_rails_present
        DetectionResult.new("rails", "bin/rails present")
      # NOTE: Intentionally ends with $ to avoid mis-matching minitest-reporters, etc. in a Rails app.
      elsif dependencies.any?(/^minitest$/)
        DetectionResult.new("minitest", "direct dependency matching /^minitest$/")
      elsif dependencies.any?(/^test-unit/)
        DetectionResult.new("test-unit", "direct dependency matching /^test-unit/")
      else
        DetectionResult.new("unknown", "no test library detected")
      end
    end

    #: (Array[String] dependencies) -> DetectionResult?
    def detect_typechecker(dependencies)
      return if ENV["RUBY_LSP_BYPASS_TYPECHECKER"]
      return if dependencies.none?(/^sorbet-static/)

      DetectionResult.new("sorbet", "sorbet-static in dependencies")
    rescue Bundler::GemfileNotFound
      nil
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
