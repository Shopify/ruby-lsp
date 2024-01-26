# typed: true
# frozen_string_literal: true

require "test_helper"
require "expectations/expectations_test_runner"

class CodeLensExpectationsTest < ExpectationsTestRunner
  expectations_tests RubyLsp::Requests::CodeLens, "code_lens"

  def run_expectations(source)
    uri = URI("file://#{@_path}")
    document = RubyLsp::RubyDocument.new(source: source, version: 1, uri: uri)

    dispatcher = Prism::Dispatcher.new
    stub_test_library("minitest")
    listener = RubyLsp::Requests::CodeLens.new(uri, default_lenses_configuration, dispatcher)
    dispatcher.dispatch(document.tree)
    listener.perform
  end

  def test_command_generation_for_test_unit
    stub_test_library("test-unit")
    source = <<~RUBY
      class FooTest < Test::Unit::TestCase
        def test_bar; end
      end
    RUBY
    uri = URI("file:///fake.rb")

    document = RubyLsp::RubyDocument.new(source: source, version: 1, uri: uri)

    dispatcher = Prism::Dispatcher.new
    listener = RubyLsp::Requests::CodeLens.new(uri, default_lenses_configuration, dispatcher)
    dispatcher.dispatch(document.tree)
    response = listener.perform

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

    document = RubyLsp::RubyDocument.new(source: source, version: 1, uri: uri)

    dispatcher = Prism::Dispatcher.new
    stub_test_library("unknown")
    listener = RubyLsp::Requests::CodeLens.new(uri, default_lenses_configuration, dispatcher)
    dispatcher.dispatch(document.tree)
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

    document = RubyLsp::RubyDocument.new(source: source, version: 1, uri: uri)

    dispatcher = Prism::Dispatcher.new
    stub_test_library("rspec")
    listener = RubyLsp::Requests::CodeLens.new(uri, default_lenses_configuration, dispatcher)
    dispatcher.dispatch(document.tree)
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

    document = RubyLsp::RubyDocument.new(source: source, version: 1, uri: uri)

    dispatcher = Prism::Dispatcher.new
    stub_test_library("minitest")
    listener = RubyLsp::Requests::CodeLens.new(uri, default_lenses_configuration, dispatcher)
    dispatcher.dispatch(document.tree)
    response = listener.perform

    assert_empty(response)
  end

  def test_skip_gemfile_links
    uri = URI("file:///Gemfile")
    document = RubyLsp::RubyDocument.new(uri: uri, source: <<~RUBY, version: 1)
      gem 'minitest'
    RUBY

    dispatcher = Prism::Dispatcher.new
    lenses_configuration = RubyLsp::RequestConfig.new({ gemfileLinks: false })
    listener = RubyLsp::Requests::CodeLens.new(uri, lenses_configuration, dispatcher)
    dispatcher.dispatch(document.tree)
    response = listener.perform
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
      })

      assert_nil(response.error, response.error&.full_message)
      response = response.response

      assert_equal(response.size, 4)
      assert_match("Run", response[0].command.title)
      assert_match("Run In Terminal", response[1].command.title)
      assert_match("Debug", response[2].command.title)
      assert_match("Run Test", response[3].command.title)
    end
  end

  private

  def default_lenses_configuration
    RubyLsp::RequestConfig.new({ gemfileLinks: true })
  end

  def create_code_lens_addon
    Class.new(RubyLsp::Addon) do
      def create_code_lens_listener(response_builder, uri, dispatcher)
        raise "uri can't be nil" unless uri

        klass = Class.new do
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
        end

        T.unsafe(klass).new(response_builder, uri, dispatcher)
      end
    end
  end

  def stub_test_library(name)
    Singleton.__init__(RubyLsp::DependencyDetector)
    RubyLsp::DependencyDetector.instance.stubs(:detected_test_library).returns(name)
  end
end
