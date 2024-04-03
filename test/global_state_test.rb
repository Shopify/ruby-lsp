# typed: true
# frozen_string_literal: true

require "test_helper"

module RubyLsp
  class GlobalStateTest < Minitest::Test
    def test_detects_no_test_library_when_there_are_no_dependencies
      stub_dependencies({})

      assert_equal("unknown", GlobalState.new.test_library)
    end

    def test_detects_minitest
      stub_dependencies("minitest" => "1.2.3")

      assert_equal("minitest", GlobalState.new.test_library)
    end

    def test_does_not_detect_minitest_related_gems_as_minitest
      stub_dependencies("minitest-reporters" => "1.2.3")

      assert_equal("unknown", GlobalState.new.test_library)
    end

    def test_detects_test_unit
      stub_dependencies("test-unit" => "1.2.3")

      assert_equal("test-unit", GlobalState.new.test_library)
    end

    def test_detects_dependencies_in_gemspecs
      assert(GlobalState.new.direct_dependency?(/^prism$/))
    end

    def test_detects_rails_if_both_rails_and_minitest_are_present
      stub_dependencies("minitest" => "1.2.3", "rails" => "1.2.3")

      assert_equal("rails", GlobalState.new.test_library)
    end

    def test_detects_rspec_if_both_rails_and_rspec_are_present
      stub_dependencies("rspec" => "1.2.3", "rails" => "1.2.3")

      assert_equal("rspec", GlobalState.new.test_library)
    end

    def test_direct_dependency_returns_false_outside_of_bundle
      File.expects(:file?).at_least_once.returns(false)
      stub_dependencies({})
      refute(GlobalState.new.direct_dependency?(/^ruby-lsp/))
    end

    private

    def stub_dependencies(dependencies)
      Bundler.locked_gems.stubs(dependencies: dependencies)
    end
  end
end
