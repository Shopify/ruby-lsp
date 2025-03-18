# typed: true
# frozen_string_literal: true

begin
  require "test/unit"
  require "test/unit/ui/testrunner"
rescue LoadError
  return
end

require_relative "test_reporter"
require "ruby_indexer/lib/ruby_indexer/uri"

module RubyLsp
  class TestRunner < ::Test::Unit::UI::TestRunner
    private

    #: (::Test::Unit::TestCase test) -> void
    def test_started(test)
      current_test = test
      @current_uri = uri_for_test(current_test)
      return unless @current_uri

      @current_test_id = "#{current_test.class.name}##{current_test.method_name}"
      TestReporter.start_test(
        id: @current_test_id,
        uri: @current_uri,
      )
    end

    #: (::Test::Unit::TestCase test) -> void
    def test_finished(test)
      if test.passed?
        TestReporter.record_pass(
          id: @current_test_id,
          uri: @current_uri,
        )
      end
    end

    #: (::Test::Unit::Failure | ::Test::Unit::Error | ::Test::Unit::Pending result) -> void
    def result_fault(result)
      case result
      when ::Test::Unit::Failure
        record_failure(result)
      when ::Test::Unit::Error
        record_error(result)
      when ::Test::Unit::Pending
        record_skip(result)
      end
    end

    #: (::Test::Unit::Failure failure) -> void
    def record_failure(failure)
      TestReporter.record_fail(
        id: @current_test_id,
        message: failure.message,
        uri: @current_uri,
      )
    end

    #: (::Test::Unit::Error error) -> void
    def record_error(error)
      TestReporter.record_error(
        id: @current_test_id,
        message: error.message,
        uri: @current_uri,
      )
    end

    #: (::Test::Unit::Pending pending) -> void
    def record_skip(pending)
      TestReporter.record_skip(id: @current_test_id, uri: @current_uri)
    end

    #: (::Test::Unit::TestCase test) -> URI::Generic?
    def uri_for_test(test)
      location = test.method(test.method_name).source_location
      return unless location # TODO: when might this be nil?

      file, _line = location
      return if file.start_with?("(eval at ") # test is dynamically defined (TODO: better way to check?)

      absolute_path = File.expand_path(file, Dir.pwd)
      URI::Generic.from_path(path: absolute_path)
    end

    #: -> void
    def attach_to_mediator
      @mediator.add_listener(Test::Unit::TestResult::FAULT, &method(:result_fault))
      @mediator.add_listener(Test::Unit::TestCase::STARTED_OBJECT, &method(:test_started))
      @mediator.add_listener(Test::Unit::TestCase::FINISHED_OBJECT, &method(:test_finished))
    end
  end
end

Test::Unit::AutoRunner.register_runner(:ruby_lsp) { |_auto_runner| RubyLsp::TestRunner }
Test::Unit::AutoRunner.default_runner = :ruby_lsp
