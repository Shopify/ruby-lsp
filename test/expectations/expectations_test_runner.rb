# typed: true
# frozen_string_literal: true

# TODO: how to pass arguments to the test runner? See for example `CodeActionsTest`

class ExpectationsTestRunner < Minitest::Test
  TEST_EXP_DIR = "test/expectations"
  TEST_FIXTURES_DIR = "test/fixtures"
  TEST_FIXTURES_GLOB = File.join(TEST_FIXTURES_DIR, "**", "*.rb")

  class << self
    def expectations_tests(handler_class, expectation_suffix)
      class_eval(<<~RB)
        module ExpectationsRunnerMethods
          def run_expectations(source)
            document = RubyLsp::Document.new(source)
            #{handler_class}.new(document).run
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

        required_ruby_version = ruby_requirement_magic_comment_version(path)
        if required_ruby_version && RUBY_VERSION < required_ruby_version
          class_eval(<<~RB)
            def test_#{expectation_suffix}_#{test_name}
              skip "Fixture requires Ruby v#{required_ruby_version} while currently running v#{RUBY_VERSION}"
            end
          RB
        elsif File.file?(expectation_path)
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

    def ruby_requirement_magic_comment_version(fixture_path)
      File.read(fixture_path)
        .lines
        .first
        &.match(/^#\s*required_ruby_version:\s*(?<version>\d+\.\d+(\.\d+)?)$/)
        &.named_captures
        &.fetch("version")
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
      # Values are not JSON, just print the raw values
      $stderr.puts "########## Expected ##########"
      $stderr.puts expected
      $stderr.puts "##########  Actual  ##########"
      $stderr.puts actual
      $stderr.puts "##############################"
    end

    res
  end

  def json_expectations(expected_json_string)
    return {} if expected_json_string.empty?

    JSON.parse(expected_json_string)
  end
end
