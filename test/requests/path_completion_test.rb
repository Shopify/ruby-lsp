# typed: true
# frozen_string_literal: true

require "test_helper"

class PathCompletionTest < Minitest::Test
  def test_completion_command
    prefix = "foo/"

    document = RubyLsp::Document.new(<<~RUBY, 1, "file:///fake.rb")
      require "#{prefix}"
    RUBY

    position = {
      line: 0,
      character: document.source.rindex('"') || 0,
    }

    result = with_file_structure do
      RubyLsp::Requests::PathCompletion.new(document, position).run
    end

    expected = [
      path_completion("foo/bar", prefix, position),
      path_completion("foo/baz", prefix, position),
      path_completion("foo/quux", prefix, position),
      path_completion("foo/support/bar", prefix, position),
      path_completion("foo/support/baz", prefix, position),
      path_completion("foo/support/quux", prefix, position),
    ]

    assert_equal(expected.to_json, result.to_json)
  end

  def test_completion_call
    prefix = "foo/"

    document = RubyLsp::Document.new(+<<~RUBY, 1, "file:///fake.rb")
      require("#{prefix}")
    RUBY

    position = {
      line: 0,
      character: document.source.rindex('"') || 0,
    }

    result = with_file_structure do
      RubyLsp::Requests::PathCompletion.new(document, position).run
    end

    expected = [
      path_completion("foo/bar", prefix, position),
      path_completion("foo/baz", prefix, position),
      path_completion("foo/quux", prefix, position),
      path_completion("foo/support/bar", prefix, position),
      path_completion("foo/support/baz", prefix, position),
      path_completion("foo/support/quux", prefix, position),
    ]

    assert_equal(expected.to_json, result.to_json)
  end

  def test_completion_command_call
    prefix = "foo/"

    document = RubyLsp::Document.new(+<<~RUBY, 1, "file:///fake.rb")
      Kernel.require "#{prefix}"
    RUBY

    position = {
      line: 0,
      character: document.source.rindex('"') || 0,
    }

    result = with_file_structure do
      RubyLsp::Requests::PathCompletion.new(document, position).run
    end

    expected = [
      path_completion("foo/bar", prefix, position),
      path_completion("foo/baz", prefix, position),
      path_completion("foo/quux", prefix, position),
      path_completion("foo/support/bar", prefix, position),
      path_completion("foo/support/baz", prefix, position),
      path_completion("foo/support/quux", prefix, position),
    ]

    assert_equal(expected.to_json, result.to_json)
  end

  def test_completion_with_partial_path
    prefix = "foo/suppo"

    document = RubyLsp::Document.new(+<<~RUBY, 1, "file:///fake.rb")
      require "#{prefix}"
    RUBY

    position = {
      line: 0,
      character: document.source.rindex('"') || 0,
    }

    result = with_file_structure do
      RubyLsp::Requests::PathCompletion.new(document, position).run
    end

    expected = [
      path_completion("foo/support/bar", prefix, position),
      path_completion("foo/support/baz", prefix, position),
      path_completion("foo/support/quux", prefix, position),
    ]

    assert_equal(expected.to_json, result.to_json)
  end

  def test_completion_does_not_fail_when_there_are_syntax_errors
    document = RubyLsp::Document.new(+<<~RUBY, 1, "file:///fake.rb")
      require "ruby_lsp/requests/"

      def foo
    RUBY

    position = {
      line: 0,
      character: 21,
    }

    result = RubyLsp::Requests::PathCompletion.new(document, position).run
    assert_empty(result)
  end

  private

  def with_file_structure(&block)
    Dir.mktmpdir("path_completion_test") do |tmpdir|
      $LOAD_PATH << tmpdir

      # Set up folder structure like this
      # <tmpdir>
      # |-- foo
      # |   |-- bar.rb
      # |   |-- baz.rb
      # |   |-- quux.rb
      # |   |-- support
      # |       |-- bar.rb
      # |       |-- baz.rb
      # |       |-- quux.rb
      FileUtils.mkdir_p(tmpdir + "/foo/support")
      FileUtils.touch([
        tmpdir + "/foo/bar.rb",
        tmpdir + "/foo/baz.rb",
        tmpdir + "/foo/quux.rb",
        tmpdir + "/foo/support/bar.rb",
        tmpdir + "/foo/support/baz.rb",
        tmpdir + "/foo/support/quux.rb",
      ])

      return block.call
    ensure
      $LOAD_PATH.delete(tmpdir)
    end
  end

  def path_completion(path, prefix, position)
    LanguageServer::Protocol::Interface::CompletionItem.new(
      label: path,
      text_edit: LanguageServer::Protocol::Interface::TextEdit.new(
        range: LanguageServer::Protocol::Interface::Range.new(
          start: position,
          end: position,
        ),
        new_text: path.delete_prefix(prefix),
      ),
      kind: LanguageServer::Protocol::Constant::CompletionItemKind::REFERENCE,
    )
  end
end
