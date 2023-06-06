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
        if direct_dependency?(/^minitest/)
          "minitest"
        elsif direct_dependency?(/^test-unit/)
          "test-unit"
        elsif direct_dependency?(/^rspec/)
          "rspec"
        else
          warn("WARNING: No test library detected. Assuming minitest.")
          "minitest"
        end
      end

      sig { params(gem_pattern: Regexp).returns(T::Boolean) }
      def direct_dependency?(gem_pattern)
        Bundler.locked_gems.dependencies.keys.grep(gem_pattern).any?
      end
    end
  end
end
