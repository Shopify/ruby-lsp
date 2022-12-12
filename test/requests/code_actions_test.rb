# typed: true
# frozen_string_literal: true

require "test_helper"
require "ruby_lsp/requests/support/rubocop_diagnostics_runner"

class CodeActionsTest < Minitest::Test
  def test_diagnostic_calls_are_cached
    document = RubyLsp::Document.new(<<~RUBY)
      class Foo
        def bar
          a = 123
          b = a + 321
          a ** b
        end
      end
    RUBY

    uri = "file://#{__FILE__}"
    @counter = 0
    increment_counter = ->(_uri, _document) {
      @counter += 1
      []
    }

    # If diagnostics is being properly cached, then we should only see the increment_counter block invoked once for the
    # same URI, no matter how many times we invoke it and with which range
    RubyLsp::Requests::Support::RuboCopDiagnosticsRunner.instance.stub(:run, increment_counter) do
      RubyLsp::Requests::CodeActions.new(uri, document, 1..3).run
      RubyLsp::Requests::CodeActions.new(uri, document, 2..3).run
      RubyLsp::Requests::CodeActions.new(uri, document, 2..4).run
      RubyLsp::Requests::CodeActions.new(uri, document, 3..5).run
    end

    assert_equal(1, @counter)
  end
end
