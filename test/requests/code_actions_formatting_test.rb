# typed: true
# frozen_string_literal: true

require "test_helper"
require_relative "support/expectations_test_runner"

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

  def test_no_disable_line_for_self_resolving_cops
    global_state = RubyLsp::GlobalState.new
    global_state.apply_options({
      initializationOptions: { linters: ["rubocop_internal"] },
    })
    global_state.register_formatter(
      "rubocop_internal",
      RubyLsp::Requests::Support::RuboCopFormatter.new,
    )

    source = <<~RUBY
      #
      def foo; end
    RUBY

    document = RubyLsp::RubyDocument.new(
      source: source,
      version: 1,
      uri: URI::Generic.from_path(path: __FILE__),
      global_state: global_state,
    )

    diagnostics = RubyLsp::Requests::Diagnostics.new(global_state, document).perform
    rubocop_diagnostics = diagnostics&.select { _1.attributes[:source] == "RuboCop" }
    diagnostic = rubocop_diagnostics&.find { |d| d.attributes[:code] == "Layout/EmptyComment" }

    assert(diagnostic, "Expected Layout/EmptyComment diagnostic to be present")

    range = diagnostic #: as !nil
      .range.to_hash.transform_values(&:to_hash)
    result = RubyLsp::Requests::CodeActions.new(document, range, {
      diagnostics: [JSON.parse(diagnostic.to_json, symbolize_names: true)],
    }).perform

    untyped_result = result #: untyped
    disable_action = untyped_result.find do |ca|
      ca.respond_to?(:[]) && ca[:title] == "Disable Layout/EmptyComment for this line"
    end

    assert_nil(disable_action, "Should not offer disable action for self-resolving cops")
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

  #: (String diagnostic_code, String code_action_title, String source, String expected) -> untyped
  def assert_corrects_to_expected(diagnostic_code, code_action_title, source, expected)
    global_state = RubyLsp::GlobalState.new
    global_state.apply_options({
      initializationOptions: { linters: ["rubocop_internal"] },
    })
    global_state.register_formatter(
      "rubocop_internal",
      RubyLsp::Requests::Support::RuboCopFormatter.new,
    )

    document = RubyLsp::RubyDocument.new(
      source: source.dup,
      version: 1,
      uri: URI::Generic.from_path(path: __FILE__),
      global_state: global_state,
    )

    diagnostics = RubyLsp::Requests::Diagnostics.new(global_state, document).perform
    # The source of the returned attributes may be RuboCop or Prism. Prism diagnostics don't have a code.
    rubocop_diagnostics = diagnostics&.select { _1.attributes[:source] == "RuboCop" }
    diagnostic = rubocop_diagnostics&.find { |d| d.attributes[:code] && (d.code == diagnostic_code) } #: as !nil
    range = diagnostic.range.to_hash.transform_values(&:to_hash)
    result = RubyLsp::Requests::CodeActions.new(document, range, {
      diagnostics: [JSON.parse(diagnostic.to_json, symbolize_names: true)],
    }).perform

    # CodeActions#run returns Array<CodeAction, Hash>. We're interested in the
    # hashes here, so cast to untyped and only look at those.
    untyped_result = result #: untyped
    selected_action = untyped_result.find do |ca|
      ca.respond_to?(:[]) && ca[:title] == code_action_title
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

  #: (String name) -> [String, String]
  def load_expectation(name)
    source = File.read(File.join(TEST_FIXTURES_DIR, "#{name}.rb"))
    expected = File.read(File.join(TEST_EXP_DIR, "#{name}.exp.rb"))
    [source, expected]
  end
end
