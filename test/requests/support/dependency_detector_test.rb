# typed: true
# frozen_string_literal: true

require "test_helper"

module RubyLsp
  class DependencyDetectorTest < Minitest::Test
    def setup
      reset_dependency_detector
    end

    def test_detects_no_test_library_when_there_are_no_dependencies
      dependencies = {}
      Bundler.locked_gems.stubs(dependencies: dependencies)

      assert_equal("unknown", DependencyDetector.instance.detected_test_library)
    end

    def test_detects_minitest
      dependencies = { "minitest" => "1.2.3" }
      Bundler.locked_gems.stubs(dependencies: dependencies)

      assert_equal("minitest", DependencyDetector.instance.detected_test_library)
    end

    def test_does_not_detect_minitest_related_gems_as_minitest
      dependencies = { "minitest-reporters" => "1.2.3" }
      Bundler.locked_gems.stubs(dependencies: dependencies)

      assert_equal("unknown", DependencyDetector.instance.detected_test_library)
    end

    def test_detects_test_unit
      dependencies = { "test-unit" => "1.2.3" }
      Bundler.locked_gems.stubs(dependencies: dependencies)

      assert_equal("test-unit", DependencyDetector.instance.detected_test_library)
    end

    def test_detects_rails_if_both_rails_and_minitest_are_present
      dependencies = { "minitest" => "1.2.3", "rails" => "1.2.3" }
      Bundler.locked_gems.stubs(dependencies: dependencies)

      assert_equal("rails", DependencyDetector.instance.detected_test_library)
    end

    def test_direct_dependency_returns_false_outside_of_bundle
      File.expects(:file?).at_least_once.returns(false)
      refute(DependencyDetector.instance.direct_dependency?(/^ruby-lsp/))
    end
  end
end
