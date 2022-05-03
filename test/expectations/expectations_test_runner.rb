# frozen_string_literal: true

# TODO: how to pass arguments to the test runner? See for example `CodeActionsTest`

class ExpectationsTestRunner < Minitest::Test
  TEST_EXP_DIR = "test/expectations"
  TEST_FIXTURES_DIR = "test/fixtures"
  TEST_FIXTURES_GLOB = File.join(TEST_FIXTURES_DIR, "**", "*.rb")

  def self.expectations_tests(handler_class, expectation_suffix)
    class_eval(<<~RB)
      module ExpectationsRunnerMethods
        def run_expectations(source)
          document = RubyLsp::Document.new(source)
          #{handler_class}.run(document)
        end

        def assert_expectations(source, expected)
          actual = run_expectations(source)
          assert_equal(JSON.parse(expected), JSON.parse(actual.to_json))
        end
      end

      include ExpectationsRunnerMethods
    RB

    Dir.glob(TEST_FIXTURES_GLOB).each do |path|
      test_name = File.basename(path, ".rb")

      expectations_dir = File.join(TEST_EXP_DIR, expectation_suffix)
      unless File.directory?(expectations_dir)
        raise "Expectations directory #{expectations_dir} does not exist"
      end

      expectation_path = File.join(expectations_dir, "#{test_name}.exp")

      if File.file?(expectation_path)
        class_eval(<<~RB)
          def test_#{expectation_suffix}_#{test_name}
            source = File.read("#{path}")
            expected = File.read("#{expectation_path}")
            assert_expectations(source, expected)
          end
        RB
      else
        class_eval(<<~RB)
          def test_#{expectation_suffix}_#{test_name}_does_not_raise
            source = File.read("#{path}")
            run_expectations(source)
          end
        RB
      end
    end
  end

  private

  def diff(expected, actual)
    res = super
    return unless res

    begin
      # If the values are JSON we want to pretty print them
      expected_obj = JSON.parse(expected)
      $stderr.puts "########## Expected ##########"
      $stderr.puts JSON.pretty_generate(expected_obj)
      $stderr.puts "##########  Actual  ##########"
      actual_obj = JSON.parse(actual)
      $stderr.puts JSON.pretty_generate(actual_obj)
      $stderr.puts "##############################"
    rescue
      # Values are not JSON, skip the pretty printing
    end

    res
  end
end
