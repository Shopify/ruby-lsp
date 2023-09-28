# typed: strict
# frozen_string_literal: true

require "singleton"

module RubyLsp
  class DependencyDetector
    include Singleton
    extend T::Sig

    attr_reader :detected_formatter, :detected_test_library

    sig { void }
    def initialize
      @dependency_keys = T.let(nil, T.nilable(T::Array[String]))
      @detected_formatter = T.let(detected_formatter, String)
      @detected_test_library = T.let(detected_test_library, String)
      @typechecker = T.let(typechecker?, T::Boolean)
    end

    sig { returns(T::Boolean) }
    def typechecker?
      @typechecker
    end

    sig { returns(String) }
    def detected_formatter
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
    def detected_test_library
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
      dependency_keys.grep(gem_pattern).any?
    end

    sig { returns(T::Boolean) }
    def typechecker?
      direct_dependency?(/^sorbet/) || direct_dependency?(/^sorbet-static-and-runtime/)
    end

    private

    sig { returns(T::Array[String]) }
    def dependency_keys
      @dependency_keys ||= begin
        Bundler.with_original_env { Bundler.default_gemfile }
        Bundler.locked_gems.dependencies.keys
      rescue Bundler::GemfileNotFound
        []
      end
    end
  end
end
