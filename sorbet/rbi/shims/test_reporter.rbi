# typed: true

class RubyLsp::LspReporter
  # https://code.visualstudio.com/api/references/vscode-api#Position
  Position = T.type_alias { { line: Integer, character: Integer } }

  # https://code.visualstudio.com/api/references/vscode-api#Range
  Range = T.type_alias { { start: Position, end: Position } }

  # https://code.visualstudio.com/api/references/vscode-api#BranchCoverage
  BranchCoverage = T.type_alias { { executed: Integer, label: String, location: Range } }

  # https://code.visualstudio.com/api/references/vscode-api#StatementCoverage
  StatementCoverage = T.type_alias { { executed: Integer, location: Position, branches: T::Array[BranchCoverage] } }
end

class ::Test::Unit::UI::Console::TestRunner
  def initialize(suite, options = T.unsafe(nil))
    @mediator = T.let(T.unsafe(nil), Test::Unit::UI::TestRunnerMediator)
  end
end

class RubyLsp::TestUnitReporter
  def initialize(suite, options = T.unsafe(nil))
    @current_uri = T.let(nil, T.nilable(URI::Generic))
    @current_test_id = T.let(nil, T.nilable(String))
  end
end
