# typed: true
# frozen_string_literal: true

require "test_helper"
require "expectations/expectations_test_runner"

class CodeLensExpectationsTest < ExpectationsTestRunner
  expectations_tests RubyLsp::Requests::CodeLens, "code_lens"

  def run_expectations(source)
    uri = URI("file://#{@_path}")
    document = RubyLsp::Document.new(source: source, version: 1, uri: uri)

    emitter = RubyLsp::EventEmitter.new
    RubyLsp::DependencyDetector.instance.stubs(:detected_test_library).returns("minitest")
    listener = RubyLsp::Requests::CodeLens.new(uri, emitter, @message_queue)
    emitter.visit(document.tree)
    listener.response
  end

  def test_command_generation_for_test_unit
    source = <<~RUBY
      class FooTest < Test::Unit::TestCase
        def test_bar; end
      end
    RUBY
    uri = URI("file:///fake.rb")

    document = RubyLsp::Document.new(source: source, version: 1, uri: uri)

    emitter = RubyLsp::EventEmitter.new
    RubyLsp::DependencyDetector.instance.stubs(:detected_test_library).returns("test-unit")
    listener = RubyLsp::Requests::CodeLens.new(uri, emitter, @message_queue)
    emitter.visit(document.tree)
    response = listener.response

    assert_equal(6, response.size)

    assert_equal("Run In Terminal", T.must(response[1]).command.title)
    assert_equal("bundle exec ruby -Itest /fake.rb --testcase /FooTest/", T.must(response[1]).command.arguments[2])
    assert_equal("Run In Terminal", T.must(response[4]).command.title)
    assert_equal(
      "bundle exec ruby -Itest /fake.rb --testcase /FooTest/ --name test_bar",
      T.must(response[4]).command.arguments[2],
    )
  end

  def test_no_code_lens_for_unknown_test_framework
    source = <<~RUBY
      class FooTest < Test::Unit::TestCase
        def test_bar; end
      end
    RUBY
    uri = URI("file:///fake.rb")

    document = RubyLsp::Document.new(source: source, version: 1, uri: uri)

    emitter = RubyLsp::EventEmitter.new
    RubyLsp::DependencyDetector.instance.stubs(:detected_test_library).returns("rspec")
    listener = RubyLsp::Requests::CodeLens.new(uri, emitter, @message_queue)
    emitter.visit(document.tree)
    response = listener.response

    assert_empty(response)
  end

  def test_no_code_lens_for_rspec
    source = <<~RUBY
      class FooTest < Test::Unit::TestCase
        def test_bar; end
      end
    RUBY
    uri = URI("file:///fake.rb")

    document = RubyLsp::Document.new(source: source, version: 1, uri: uri)

    emitter = RubyLsp::EventEmitter.new
    RubyLsp::DependencyDetector.instance.stubs(:detected_test_library).returns("rspec")
    listener = RubyLsp::Requests::CodeLens.new(uri, emitter, @message_queue)
    emitter.visit(document.tree)
    response = listener.response

    assert_empty(response)
  end

  def test_no_code_lens_for_unsaved_files
    source = <<~RUBY
      class FooTest < Test::Unit::TestCase
        def test_bar; end
      end
    RUBY
    uri = URI::Generic.build(scheme: "untitled", opaque: "Untitled-1")

    document = RubyLsp::Document.new(source: source, version: 1, uri: uri)

    emitter = RubyLsp::EventEmitter.new
    RubyLsp::DependencyDetector.instance.stubs(:detected_test_library).returns("minitest")
    listener = RubyLsp::Requests::CodeLens.new(uri, emitter, @message_queue)
    emitter.visit(document.tree)
    response = listener.response

    assert_empty(response)
  end

  def test_code_lens_addons
    source = <<~RUBY
      class Test < Minitest::Test; end
    RUBY

    test_addon(:create_code_lens_addon, source: source) do |executor|
      response = executor.execute({
        method: "textDocument/codeLens",
        params: { textDocument: { uri: "file:///fake.rb" }, position: { line: 1, character: 2 } },
      }).response

      assert_equal(response.size, 4)
      assert_match("Run", response[0].command.title)
      assert_match("Run In Terminal", response[1].command.title)
      assert_match("Debug", response[2].command.title)
      assert_match("Run Test", response[3].command.title)
    end
  end

  private

  def create_code_lens_addon
    Class.new(RubyLsp::Addon) do
      def activate; end

      def name
        "CodeLensAddon"
      end

      def create_code_lens_listener(uri, emitter, message_queue)
        raise "uri can't be nil" unless uri

        klass = Class.new(RubyLsp::Listener) do
          attr_reader :_response

          def initialize(uri, emitter, message_queue)
            super(emitter, message_queue)
            emitter.register(self, :on_class)
          end

          def on_class(node)
            T.bind(self, RubyLsp::Listener[T.untyped])

            @_response = [RubyLsp::Interface::CodeLens.new(
              range: range_from_node(node),
              command: RubyLsp::Interface::Command.new(
                title: "Run #{node.constant_path.slice}",
                command: "rubyLsp.runTest",
              ),
            )]
          end
        end

        T.unsafe(klass).new(uri, emitter, message_queue)
      end
    end
  end
end
