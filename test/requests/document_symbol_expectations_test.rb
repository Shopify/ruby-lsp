# frozen_string_literal: true

require "test_helper"
require "expectations/expectations_test_runner"

class DocumentationSymbolExpectationsTest < ExpectationsTestRunner
  expectations_tests RubyLsp::Requests::DocumentSymbol, File.basename(__dir__)
end
