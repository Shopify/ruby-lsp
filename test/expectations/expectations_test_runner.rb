# frozen_string_literal: true

class ExpectationsTestRunner < Minitest::Test
  TEST_DATA_DIR = "test/data"
  TEST_DATA_GLOB = File.join(TEST_DATA_DIR, "**", "*.rb")

  TEST_EXP_DIR = "test/expectations"

  def self.expectations_tests(handler_class, expectation_suffix)
    unless method_defined?(:run_expectations)
      class_eval(<<~RB)
        def run_expectations(source)
          parsed_tree = RubyLsp::Store::ParsedTree.new(source)
          #{handler_class}.run(parsed_tree)
        end
      RB
    end

    unless method_defined?(:assert_expectations)
      class_eval(<<~RB)
        def assert_expectations(source, expected)
          actual = run_expectations(source)
          assert_equal_or_pretty_display(expected, actual)
        end
      RB
    end

    Dir.glob(TEST_DATA_GLOB).each do |path|
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
