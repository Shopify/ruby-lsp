# typed: true
# frozen_string_literal: true

require "test_helper"

class PathCompletionTest < Minitest::Test
  def test_completion_command
    document = RubyLsp::Document.new(+<<~RUBY)
      require "ruby_lsp/requests/"
    RUBY

    position = {
      line: 0,
      character: 21,
    }

    result = RubyLsp::Requests::PathCompletion.new(document, position).run
    assert_equal(path_completions("ruby_lsp/requests/").to_json, result.to_json)
  end

  def test_completion_call
    document = RubyLsp::Document.new(+<<~RUBY)
      require("ruby_lsp/requests/")
    RUBY

    position = {
      line: 0,
      character: 21,
    }

    result = RubyLsp::Requests::PathCompletion.new(document, position).run
    assert_equal(path_completions("ruby_lsp/requests/").to_json, result.to_json)
  end

  def test_completion_command_call
    document = RubyLsp::Document.new(+<<~RUBY)
      Kernel.require "ruby_lsp/requests/"
    RUBY

    position = {
      line: 0,
      character: 28,
    }

    result = RubyLsp::Requests::PathCompletion.new(document, position).run
    assert_equal(path_completions("ruby_lsp/requests/").to_json, result.to_json)
  end

  private

  def path_completions(path_stem)
    root = File.dirname(Bundler.default_gemfile) + "/lib"

    Dir["#{path_stem}**/*.rb", base: root].sort.map do |path|
      path.delete_suffix!(".rb")
      LanguageServer::Protocol::Interface::CompletionItem.new(
        label: path,
        insert_text: path.delete_prefix(path_stem),
        kind: LanguageServer::Protocol::Constant::CompletionItemKind::REFERENCE,
      )
    end
  end
end
