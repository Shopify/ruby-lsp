# typed: true
# frozen_string_literal: true

require "test_helper"

module RubyLsp
  class DependencyDetectorTest < Minitest::Test
    def test_detects_no_test_library_when_there_are_no_dependencies
      dependencies = {}
      Bundler.locked_gems.stubs(dependencies: dependencies)

      assert_equal("unknown", DependencyDetector.detected_test_library)
    end

    def test_detects_minitest
      dependencies = { "minitest" => "1.2.3" }
      Bundler.locked_gems.stubs(dependencies: dependencies)

      assert_equal("minitest", DependencyDetector.detected_test_library)
    end

    def test_does_not_detect_minitest_related_gems_as_minitest
      dependencies = { "minitest-reporters" => "1.2.3" }
      Bundler.locked_gems.stubs(dependencies: dependencies)

      assert_equal("unknown", DependencyDetector.detected_test_library)
    end

    def test_detects_test_unit
      dependencies = { "test-unit" => "1.2.3" }
      Bundler.locked_gems.stubs(dependencies: dependencies)

      assert_equal("test-unit", DependencyDetector.detected_test_library)
    end

    def test_detects_rails_if_both_rails_and_minitest_are_present
      dependencies = { "minitest" => "1.2.3", "rails" => "1.2.3" }
      Bundler.locked_gems.stubs(dependencies: dependencies)

      assert_equal("rails", DependencyDetector.detected_test_library)
    end
  end
end
