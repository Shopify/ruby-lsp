# typed: strict
# frozen_string_literal: true

require "singleton"

module RubyLsp
  class DependencyDetector
    include Singleton
    extend T::Sig

    sig { returns(String) }
    attr_reader :detected_formatter

    sig { returns(String) }
    attr_reader :detected_test_library

    sig { returns(T::Boolean) }
    attr_reader :typechecker

    sig { void }
    def initialize
      @detected_formatter = T.let(detect_formatter, String)
      @detected_test_library = T.let(detect_test_library, String)
      @typechecker = T.let(detect_typechecker, T::Boolean)
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
      # A Rails app may have a dependency on minitest, but we would instead want to use the Rails test runner provided
      # by ruby-lsp-rails.
      if direct_dependency?(/^rails$/)
        "rails"
      # NOTE: Intentionally ends with $ to avoid mis-matching minitest-reporters, etc. in a Rails app.
      elsif direct_dependency?(/^minitest$/)
        "minitest"
      elsif direct_dependency?(/^test-unit/)
        "test-unit"
      elsif direct_dependency?(/^rspec/)
        "rspec"
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

      Bundler.with_original_env do
        Bundler.locked_gems.specs.any? { |spec| spec.name == "sorbet-static" }
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
