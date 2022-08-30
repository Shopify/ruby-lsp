# typed: true
# frozen_string_literal: true

require "test_helper"
require "expectations/expectations_test_runner"

class InlayHintsExpectationsTest < ExpectationsTestRunner
  expectations_tests RubyLsp::Requests::InlayHints, "inlay_hints"

  def default_args
    [0..20]
  end
end
