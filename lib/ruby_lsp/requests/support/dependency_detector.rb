# typed: strict
# frozen_string_literal: true

module RubyLsp
  module DependencyDetector
    class << self
      extend T::Sig

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
        Bundler.with_original_env { Bundler.default_gemfile } &&
          Bundler.locked_gems.dependencies.keys.grep(gem_pattern).any?
      rescue Bundler::GemfileNotFound
        false
      end
    end
  end
end
