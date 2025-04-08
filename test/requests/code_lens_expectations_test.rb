# typed: true
# frozen_string_literal: true

require "test_helper"
require_relative "support/expectations_test_runner"

class CodeLensExpectationsTest < ExpectationsTestRunner
  expectations_tests RubyLsp::Requests::CodeLens, "code_lens"

  def run_expectations(source)
    uri = URI("file://#{@_path}")
    document = RubyLsp::RubyDocument.new(source: source, version: 1, uri: uri, global_state: @global_state)

    dispatcher = Prism::Dispatcher.new
    stub_test_library("minitest")
    listener = RubyLsp::Requests::CodeLens.new(@global_state, uri, dispatcher)
    dispatcher.dispatch(document.parse_result.value)
    listener.perform
  end

  def test_command_generation_for_minitest
    stub_test_library("minitest")
    source = <<~RUBY
      class FooTest < MiniTest::Test
        def test_bar; end
      end
    RUBY
    uri = URI("file:///test/fake.rb")

    document = RubyLsp::RubyDocument.new(source: source, version: 1, uri: uri, global_state: @global_state)

    dispatcher = Prism::Dispatcher.new
    listener = RubyLsp::Requests::CodeLens.new(@global_state, uri, dispatcher)
    dispatcher.dispatch(document.parse_result.value)
    response = listener.perform

    assert_equal(6, response.size)

    assert_equal("▶ Run In Terminal", T.must(response[1]).command.title)
    assert_equal(
      "bundle exec ruby -Itest /test/fake.rb --name \"/^FooTest(#|::)/\"",
      T.must(response[1]).command.arguments[2],
    )
    assert_equal("▶ Run In Terminal", T.must(response[4]).command.title)
    assert_equal(
      "bundle exec ruby -Itest /test/fake.rb --name FooTest#test_bar",
      T.must(response[4]).command.arguments[2],
    )
  end

  def test_command_generation_for_minitest_spec
    stub_test_library("minitest")
    source = <<~RUBY
      class FooTest < MiniTest::Spec
        describe "a" do
          it "b"
        end
      end
    RUBY
    uri = URI("file:///spec/fake.rb")

    document = RubyLsp::RubyDocument.new(source: source, version: 1, uri: uri, global_state: @global_state)

    dispatcher = Prism::Dispatcher.new
    listener = RubyLsp::Requests::CodeLens.new(@global_state, uri, dispatcher)
    dispatcher.dispatch(document.parse_result.value)
    response = listener.perform

    assert_equal(9, response.size)

    assert_equal("▶ Run In Terminal", T.must(response[1]).command.title)
    assert_equal(
      "bundle exec ruby -Ispec /spec/fake.rb --name \"/^FooTest(#|::)/\"",
      T.must(response[1]).command.arguments[2],
    )
    assert_equal("▶ Run In Terminal", T.must(response[4]).command.title)
    assert_equal(
      "bundle exec ruby -Ispec /spec/fake.rb --name \"/^FooTest::a(#|::)/\"",
      T.must(response[4]).command.arguments[2],
    )
    assert_equal("▶ Run In Terminal", T.must(response[7]).command.title)
    assert_equal(
      "bundle exec ruby -Ispec /spec/fake.rb --name \"/^FooTest::a#test_0001_b$/\"",
      T.must(response[7]).command.arguments[2],
    )
  end

  def test_command_generation_for_minitest_spec_handles_specify_alias_for_it
    stub_test_library("minitest")
    source = <<~RUBY
      describe "a" do
        specify "b"
      end
    RUBY
    uri = URI("file:///spec/fake.rb")

    document = RubyLsp::RubyDocument.new(source: source, version: 1, uri: uri, global_state: @global_state)

    dispatcher = Prism::Dispatcher.new
    listener = RubyLsp::Requests::CodeLens.new(@global_state, uri, dispatcher)
    dispatcher.dispatch(document.parse_result.value)
    response = listener.perform

    # 3 for the describe, 3 for the specify
    assert_equal(6, response.size)
  end

  def test_command_generation_for_test_unit
    stub_test_library("test-unit")
    source = <<~RUBY
      class FooTest < Test::Unit::TestCase
        def test_bar; end
      end
    RUBY
    uri = URI("file:///test/fake.rb")

    document = RubyLsp::RubyDocument.new(source: source, version: 1, uri: uri, global_state: @global_state)

    dispatcher = Prism::Dispatcher.new
    listener = RubyLsp::Requests::CodeLens.new(@global_state, uri, dispatcher)
    dispatcher.dispatch(document.parse_result.value)
    response = listener.perform

    assert_equal(6, response.size)

    assert_equal("▶ Run In Terminal", T.must(response[1]).command.title)
    assert_equal("bundle exec ruby -Itest /test/fake.rb --testcase /FooTest/", T.must(response[1]).command.arguments[2])
    assert_equal("▶ Run In Terminal", T.must(response[4]).command.title)
    assert_equal(
      "bundle exec ruby -Itest /test/fake.rb --testcase /FooTest/ --name test_bar",
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

    document = RubyLsp::RubyDocument.new(source: source, version: 1, uri: uri, global_state: @global_state)

    dispatcher = Prism::Dispatcher.new
    stub_test_library("unknown")
    listener = RubyLsp::Requests::CodeLens.new(@global_state, uri, dispatcher)
    dispatcher.dispatch(document.parse_result.value)
    response = listener.perform

    assert_empty(response)
  end

  def test_no_code_lens_for_rspec
    source = <<~RUBY
      class FooTest < Test::Unit::TestCase
        def test_bar; end
      end
    RUBY
    uri = URI("file:///fake.rb")

    document = RubyLsp::RubyDocument.new(source: source, version: 1, uri: uri, global_state: @global_state)

    dispatcher = Prism::Dispatcher.new
    stub_test_library("rspec")
    listener = RubyLsp::Requests::CodeLens.new(@global_state, uri, dispatcher)
    dispatcher.dispatch(document.parse_result.value)
    response = listener.perform

    assert_empty(response)
  end

  def test_no_code_lens_for_unsaved_files
    source = <<~RUBY
      class FooTest < Test::Unit::TestCase
        def test_bar; end
      end
    RUBY
    uri = URI::Generic.build(scheme: "untitled", opaque: "Untitled-1")

    document = RubyLsp::RubyDocument.new(source: source, version: 1, uri: uri, global_state: @global_state)

    dispatcher = Prism::Dispatcher.new
    stub_test_library("minitest")
    listener = RubyLsp::Requests::CodeLens.new(@global_state, uri, dispatcher)
    dispatcher.dispatch(document.parse_result.value)
    response = listener.perform

    assert_empty(response)
  end

  def test_no_code_lens_for_unsaved_specs
    source = <<~RUBY
      describe FooTest < Minitest::Spec
        it "does something"; end
      end
    RUBY
    uri = URI::Generic.build(scheme: "untitled", opaque: "Untitled-1")

    document = RubyLsp::RubyDocument.new(source: source, version: 1, uri: uri, global_state: @global_state)

    dispatcher = Prism::Dispatcher.new
    stub_test_library("minitest")
    listener = RubyLsp::Requests::CodeLens.new(@global_state, uri, dispatcher)
    dispatcher.dispatch(document.parse_result.value)
    response = listener.perform

    assert_empty(response)
  end

  def test_code_lens_addons
    source = <<~RUBY
      class Test < Minitest::Test; end
    RUBY

    create_code_lens_addon

    with_server(source) do |server, uri|
      server.process_message({
        id: 1,
        method: "textDocument/codeLens",
        params: { textDocument: { uri: uri }, position: { line: 1, character: 2 } },
      })

      # Pop the re-indexing notification
      server.pop_response

      result = server.pop_response
      assert_instance_of(RubyLsp::Result, result)

      response = result.response

      assert_equal(response.size, 4)
      assert_match("▶ Run", response[0].command.title)
      assert_match("▶ Run In Terminal", response[1].command.title)
      assert_match("Debug", response[2].command.title)
      assert_match("Run Test", response[3].command.title)
    end
  end

  def test_no_code_lens_for_nested_defs
    stub_test_library("test-unit")
    source = <<~RUBY
      class FooTest < Test::Unit::TestCase
        def test_bar
          def test_baz; end
        end
      end
    RUBY
    uri = URI("file:///fake.rb")

    document = RubyLsp::RubyDocument.new(source: source, version: 1, uri: uri, global_state: @global_state)

    dispatcher = Prism::Dispatcher.new
    listener = RubyLsp::Requests::CodeLens.new(@global_state, uri, dispatcher)
    dispatcher.dispatch(document.parse_result.value)
    response = listener.perform

    assert_equal(6, response.size)
  end

  private

  def create_code_lens_addon
    Class.new(RubyLsp::Addon) do
      def create_code_lens_listener(response_builder, uri, dispatcher)
        raise "uri can't be nil" unless uri

        Class.new do
          include RubyLsp::Requests::Support::Common

          def initialize(response_builder, uri, dispatcher)
            @response_builder = response_builder
            dispatcher.register(self, :on_class_node_enter)
          end

          def on_class_node_enter(node)
            T.bind(self, RubyLsp::Requests::Support::Common)

            @response_builder << RubyLsp::Interface::CodeLens.new(
              range: range_from_node(node),
              command: RubyLsp::Interface::Command.new(
                title: "Run #{node.constant_path.slice}",
                command: "rubyLsp.runTest",
              ),
            )
          end
        end.new(response_builder, uri, dispatcher)
      end

      def activate(global_state, outgoing_queue)
      end

      def deactivate; end

      def name; end

      def version
        "0.1.0"
      end
    end
  end

  def stub_test_library(name)
    @global_state.stubs(:test_library).returns(name)
  end
end
