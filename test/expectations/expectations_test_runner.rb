# frozen_string_literal: true

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
          assert_equal_or_pretty_display(expected, actual)
        end
      end

      include ExpectationsRunnerMethods
    RB

    Dir.glob(TEST_FIXTURES_GLOB).each do |path|
      test_name = File.basename(path, ".rb")

      expectation_path = File.join(TEST_EXP_DIR, expectation_suffix, "#{test_name}.exp")

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

  def assert_equal_or_pretty_display(expected, actual)
    assert_equal(JSON.parse(expected), JSON.parse(actual.to_json))
  rescue Minitest::Assertion => e
    $stderr.puts "## Expected Output #########"
    $stderr.puts JSON.pretty_generate(actual)
    $stderr.puts "############################"
    raise e
  end
end
