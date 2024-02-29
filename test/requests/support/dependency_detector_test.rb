# typed: true
# frozen_string_literal: true

require "test_helper"

module RubyLsp
  class DependencyDetectorTest < Minitest::Test
    def teardown
      Singleton.__init__(RubyLsp::DependencyDetector)
    end

    def test_detects_no_test_library_when_there_are_no_dependencies
      stub_dependencies({})

      assert_equal("unknown", DependencyDetector.instance.detected_test_library)
    end

    def test_detects_minitest
      stub_dependencies("minitest" => "1.2.3")

      assert_equal("minitest", DependencyDetector.instance.detected_test_library)
    end

    def test_does_not_detect_minitest_related_gems_as_minitest
      stub_dependencies("minitest-reporters" => "1.2.3")

      assert_equal("unknown", DependencyDetector.instance.detected_test_library)
    end

    def test_detects_test_unit
      stub_dependencies("test-unit" => "1.2.3")

      assert_equal("test-unit", DependencyDetector.instance.detected_test_library)
    end

    def test_detects_dependencies_in_gemspecs
      assert(DependencyDetector.instance.direct_dependency?(/^prism$/))
    end

    def test_detects_rails_if_both_rails_and_minitest_are_present
      stub_dependencies("minitest" => "1.2.3", "rails" => "1.2.3")

      assert_equal("rails", DependencyDetector.instance.detected_test_library)
    end

    def test_direct_dependency_returns_false_outside_of_bundle
      File.expects(:file?).at_least_once.returns(false)
      stub_dependencies({})
      refute(DependencyDetector.instance.direct_dependency?(/^ruby-lsp/))
    end

    # TODO: add tests for `detect_formatter`

    def test_direct_dependency_on_detect_formatter
      skip "TODO"
    end

    def test_direct_dependency_on_standard_rb_toooodooo
      skip "TODO"
    end

    private

    def stub_dependencies(dependencies)
      Singleton.__init__(RubyLsp::DependencyDetector)
      Bundler.locked_gems.stubs(dependencies: dependencies)
    end
  end
end
