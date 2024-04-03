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
    attr_reader :typechecker

    sig { returns(RubyIndexer::Index) }
    attr_reader :index

    sig { void }
    def initialize
      @workspace_uri = T.let(URI::Generic.from_path(path: Dir.pwd), URI::Generic)

      @formatter = T.let(detect_formatter, String)
      @test_library = T.let(detect_test_library, String)
      @typechecker = T.let(detect_typechecker, T::Boolean)
      @index = T.let(RubyIndexer::Index.new, RubyIndexer::Index)
      @supported_formatters = T.let({}, T::Hash[String, Requests::Support::Formatter])
    end

    sig { params(identifier: String, instance: Requests::Support::Formatter).void }
    def register_formatter(identifier, instance)
      @supported_formatters[identifier] = instance
    end

    sig { returns(T.nilable(Requests::Support::Formatter)) }
    def active_formatter
      @supported_formatters[@formatter]
    end

    sig { params(options: T::Hash[Symbol, T.untyped]).void }
    def apply_options(options)
      workspace_uri = options.dig(:workspaceFolders, 0, :uri)
      @workspace_uri = URI(workspace_uri) if workspace_uri
    end

    sig { returns(String) }
    def workspace_path
      T.must(@workspace_uri.to_standardized_path)
    end

    sig { returns(String) }
    def detect_formatter
      # NOTE: Intentionally no $ at end, since we want to match rubocop-shopify, etc.
      if direct_dependency?(/^rubocop/)
        "rubocop"
      elsif direct_dependency?(/^syntax_tree$/)
        "syntax_tree"
      else
        "none"
      end
    end

    sig { returns(String) }
    def detect_test_library
      if direct_dependency?(/^rspec/)
        "rspec"
      # A Rails app may have a dependency on minitest, but we would instead want to use the Rails test runner provided
      # by ruby-lsp-rails.
      elsif direct_dependency?(/^rails$/)
        "rails"
      # NOTE: Intentionally ends with $ to avoid mis-matching minitest-reporters, etc. in a Rails app.
      elsif direct_dependency?(/^minitest$/)
        "minitest"
      elsif direct_dependency?(/^test-unit/)
        "test-unit"
      else
        "unknown"
      end
    end

    sig { params(gem_pattern: Regexp).returns(T::Boolean) }
    def direct_dependency?(gem_pattern)
      dependencies.any?(gem_pattern)
    end

    sig { returns(T::Boolean) }
    def detect_typechecker
      return false if ENV["RUBY_LSP_BYPASS_TYPECHECKER"]

      # We can't read the env from within `Bundle.with_original_env` so we need to set it here.
      ruby_lsp_env_is_test = (ENV["RUBY_LSP_ENV"] == "test")
      Bundler.with_original_env do
        sorbet_static_detected = Bundler.locked_gems.specs.any? { |spec| spec.name == "sorbet-static" }
        # Don't show message while running tests, since it's noisy
        if sorbet_static_detected && !ruby_lsp_env_is_test
          $stderr.puts("Ruby LSP detected this is a Sorbet project so will defer to Sorbet LSP for some functionality")
        end
        sorbet_static_detected
      end
    rescue Bundler::GemfileNotFound
      false
    end

    sig { returns(T::Array[String]) }
    def dependencies
      @dependencies ||= T.let(
        begin
          Bundler.with_original_env { Bundler.default_gemfile }
          Bundler.locked_gems.dependencies.keys + gemspec_dependencies
        rescue Bundler::GemfileNotFound
          []
        end,
        T.nilable(T::Array[String]),
      )
    end

    sig { returns(T::Array[String]) }
    def gemspec_dependencies
      Bundler.locked_gems.sources
        .grep(Bundler::Source::Gemspec)
        .flat_map { _1.gemspec&.dependencies&.map(&:name) }
    end
  end
end
