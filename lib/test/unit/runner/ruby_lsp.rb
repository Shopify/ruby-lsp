# typed: strict
# frozen_string_literal: true

require "test/unit"
require "test/unit/ui/testrunner"
# require "/Users/andyw8/src/github.com/test-unit/test-unit/lib/test/unit/test-suite-runner.rb"

module Test
  module Unit
    module RubyLsp
      class TestRunner < Test::Unit::UI::TestRunner
        private

        def test_suite_started(suite)
          @current_test_suite = suite
        end

        def result_pass_assertion(result)
          # TODO: can we capture output?
          puts "pass: #{current_test_identifier}"
        end

        def result_fault(*)
          puts "result_fault"
        end

        def test_started(test)
          puts "test_started"
          @current_test = test
        end

        def test_finished(*)
          puts "test_finished"
        end

        def current_test_identifier
          "#{@current_test_suite.name}##{@current_test.method_name}"
        end

        def attach_to_mediator
          @mediator.add_listener(
            TestResult::PASS_ASSERTION,
            &method(:result_pass_assertion)
          )
          @mediator.add_listener(
            TestResult::FAULT,
            &method(:result_fault)
          )
          # @mediator.add_listener(UI::TestRunnerMediator::STARTED,
          #                        &method(:started))
          # @mediator.add_listener(TestRunnerMediator::FINISHED,
          #                        &method(:finished))
          @mediator.add_listener(
            TestCase::STARTED_OBJECT,
            &method(:test_started)
          )
          @mediator.add_listener(
            TestCase::FINISHED_OBJECT,
            &method(:test_finished)
          )
          @mediator.add_listener(
            TestSuite::STARTED_OBJECT,
            &method(:test_suite_started)
          )
          # @mediator.add_listener(TestSuite::FINISHED_OBJECT,
          #                        &method(:test_suite_finished))
        end
      end
    end
    # RUBYOPT=-rruby_lsp/test_unit_runner
    AutoRunner.register_runner(:ruby_lsp) do |auto_runner|
      RubyLsp::TestRunner
    end
  end
end
