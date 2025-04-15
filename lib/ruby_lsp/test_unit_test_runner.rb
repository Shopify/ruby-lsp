# typed: true
# frozen_string_literal: true

begin
  require "test/unit"
  require "test/unit/ui/testrunner"
  require "test/unit/ui/console/testrunner"
rescue LoadError
  return
end

require_relative "test_reporter"
require "ruby_indexer/lib/ruby_indexer/uri"

module RubyLsp
  class TestRunner < ::Test::Unit::UI::Console::TestRunner
    private

    #: (::Test::Unit::TestCase test) -> void
    def test_started(test)
      super

      current_test = test
      @current_uri = uri_for_test(current_test)
      return unless @current_uri

      @current_test_id = "#{current_test.class.name}##{current_test.method_name}"
      TestReporter.instance.start_test(id: @current_test_id, uri: @current_uri)
    end

    #: (::Test::Unit::TestCase test) -> void
    def test_finished(test)
      super
      TestReporter.instance.record_pass(id: @current_test_id, uri: @current_uri) if test.passed?
    end

    #: (::Test::Unit::Failure | ::Test::Unit::Error | ::Test::Unit::Pending result) -> void
    def add_fault(result)
      super

      case result
      when ::Test::Unit::Failure
        TestReporter.instance.record_fail(id: @current_test_id, message: result.message, uri: @current_uri)
      when ::Test::Unit::Error
        TestReporter.instance.record_error(id: @current_test_id, message: result.message, uri: @current_uri)
      when ::Test::Unit::Pending
        TestReporter.instance.record_skip(id: @current_test_id, uri: @current_uri)
      end
    end

    #: (Float) -> void
    def finished(elapsed_time)
      TestReporter.instance.shutdown
    end

    #: (::Test::Unit::TestCase test) -> URI::Generic?
    def uri_for_test(test)
      location = test.method(test.method_name).source_location
      return unless location

      file, _line = location
      return if file.start_with?("(eval at ")

      absolute_path = File.expand_path(file, Dir.pwd)
      URI::Generic.from_path(path: absolute_path)
    end

    #: -> void
    def attach_to_mediator
      # Events we care about
      @mediator.add_listener(Test::Unit::TestResult::FAULT, &method(:add_fault))
      @mediator.add_listener(Test::Unit::TestCase::STARTED_OBJECT, &method(:test_started))
      @mediator.add_listener(Test::Unit::TestCase::FINISHED_OBJECT, &method(:test_finished))
      @mediator.add_listener(Test::Unit::UI::TestRunnerMediator::FINISHED, &method(:finished))

      # Other events needed for the console test runner to print
      @mediator.add_listener(Test::Unit::UI::TestRunnerMediator::STARTED, &method(:started))
      @mediator.add_listener(Test::Unit::TestSuite::STARTED_OBJECT, &method(:test_suite_started))
      @mediator.add_listener(Test::Unit::TestSuite::FINISHED_OBJECT, &method(:test_suite_finished))
    end
  end
end

Test::Unit::AutoRunner.register_runner(:ruby_lsp) { |_auto_runner| RubyLsp::TestRunner }
Test::Unit::AutoRunner.default_runner = :ruby_lsp
