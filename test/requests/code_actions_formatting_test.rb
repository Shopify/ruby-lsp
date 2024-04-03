# typed: true
# frozen_string_literal: true

require "test_helper"
require "expectations/expectations_test_runner"

# Tests RuboCop disable directives - before/after on whole file
class CodeActionsFormattingTest < Minitest::Test
  TEST_EXP_DIR = File.join(ExpectationsTestRunner::TEST_EXP_DIR, "code_actions_formatting")
  TEST_FIXTURES_DIR = ExpectationsTestRunner::TEST_FIXTURES_DIR

  def test_disable_line__emoji
    assert_disable_line("emoji", "Lint/UselessAssignment")
  end

  def test_disable_line__lambda_indentation
    assert_disable_line("lambda_indentation", "Layout/IndentationConsistency")
  end

  def test_disable_line__comment_on_comment
    assert_disable_line("comment_on_comment", "Layout/CommentIndentation")
  end

  def test_disable_line__multiline_array
    assert_disable_line("multiline_array", "Layout/IndentationConsistency")
  end

  def test_disable_line__line_disable_existing
    assert_disable_line("line_disable_existing", "Lint/UselessAssignment")
  end

  def test_disable_line__multiline_string
    skip("Incompatible with inline RuboCop comment")
    assert_disable_line("multiline_string", "Lint/Void")
  end

  def test_disable_line__continuation
    skip("Incompatible with inline RuboCop comment")
    assert_disable_line("continuation", "Layout/SpaceAroundOperators")
  end

  private

  def assert_disable_line(fixture, cop_name)
    assert_fixtures_match(
      "rubocop_#{fixture}",
      cop_name,
      "Disable #{cop_name} for this line",
    )
  end

  def assert_fixtures_match(name, diagnostic_code, code_action_title)
    actual, expected = load_expectation(name)
    assert_corrects_to_expected(
      diagnostic_code,
      code_action_title,
      actual,
      expected,
    )
  end

  sig do
    params(
      diagnostic_code: String,
      code_action_title: String,
      source: String,
      expected: String,
    ).returns(T.untyped)
  end
  def assert_corrects_to_expected(diagnostic_code, code_action_title, source, expected)
    document = RubyLsp::RubyDocument.new(
      source: source.dup,
      version: 1,
      uri: URI::Generic.from_path(path: __FILE__),
      encoding: Encoding::UTF_16LE,
    )

    global_state = RubyLsp::GlobalState.new
    global_state.formatter = "rubocop"
    global_state.register_formatter(
      "rubocop",
      RubyLsp::Requests::Support::RuboCopFormatter.instance,
    )

    diagnostics = RubyLsp::Requests::Diagnostics.new(global_state, document).perform
    diagnostic = T.must(T.must(diagnostics).find { |d| d.code == diagnostic_code })
    range = diagnostic.range.to_hash.transform_values(&:to_hash)
    result = RubyLsp::Requests::CodeActions.new(document, range, {
      diagnostics: [JSON.parse(T.must(diagnostic).to_json, symbolize_names: true)],
    }).perform

    # CodeActions#run returns Array<CodeAction, Hash>. We're interested in the
    # hashes here, so cast to untyped and only look at those.
    untyped_result = T.let(result, T.untyped)
    selected_action = untyped_result.find do |ca|
      code_action = T.let(ca, T.untyped)
      code_action.respond_to?(:[]) && code_action[:title] == code_action_title
    end

    # transform edits from lsp to the format RubyLsp::Document wants them
    # this doesn't work with multiple edits if any edits add lines
    edits = selected_action.dig(:edit, :documentChanges).flat_map do |doc_change|
      doc_change[:edits].map do |edit|
        { range: edit[:range], text: edit[:newText] }
      end
    end

    document.push_edits(edits, version: 2)
    # if document.source != expected
    #   $stderr.puts("\n### #{@NAME.sub("test_", "")} ###")
    #   $stderr.puts("#### ACTUAL ####\n#{document.source}\n")
    #   $stderr.puts("#### EXPECTED ####\n#{expected}\n")
    # end

    assert_equal(document.source, expected)
  end

  sig { params(name: String).returns([String, String]) }
  def load_expectation(name)
    source = File.read(File.join(TEST_FIXTURES_DIR, "#{name}.rb"))
    expected = File.read(File.join(TEST_EXP_DIR, "#{name}.exp.rb"))
    [source, expected]
  end
end
