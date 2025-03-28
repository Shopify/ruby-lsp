# typed: true

module RubyLsp::TestReporter
  # https://code.visualstudio.com/api/references/vscode-api#Position
  Position = T.type_alias { { line: Integer, character: Integer } }

  # https://code.visualstudio.com/api/references/vscode-api#Range
  Range = T.type_alias { { start: Position, end: Position } }

  # https://code.visualstudio.com/api/references/vscode-api#BranchCoverage
  BranchCoverage = T.type_alias { { executed: Integer, label: String, location: Range } }

  # https://code.visualstudio.com/api/references/vscode-api#StatementCoverage
  StatementCoverage = T.type_alias { { executed: Integer, location: Position, branches: T::Array[BranchCoverage] } }
end
