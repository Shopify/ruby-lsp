# typed: true
# frozen_string_literal: true

class ExpectationsTestRunner < Minitest::Test
  TEST_EXP_DIR = "test/expectations"
  TEST_FIXTURES_DIR = "test/fixtures"
  TEST_RUBY_LSP_FIXTURES = File.join(TEST_FIXTURES_DIR, "*.{rb,rake}")
  TEST_PRISM_FIXTURES = File.join(TEST_FIXTURES_DIR, "prism/test/prism/fixtures/**", "*.txt")

  class << self
    def expectations_tests(handler_class, expectation_suffix)
      class_eval(<<~RB, __FILE__, __LINE__ + 1)
        module ExpectationsRunnerMethods
          def run_expectations(source)
            raise "This method should be implemented in the inherited class"
          end

          def assert_expectations(source, expected)
            parsed_expected = JSON.parse(expected)
            actual = run_expectations(source)

            if ENV['WRITE_EXPECTATIONS'] && parsed_expected["result"] != JSON.parse(actual.to_json)
              File.write(@_expectation_path, JSON.pretty_generate(result: actual, params: @__params) + "\\n")
            else
              assert_equal(parsed_expected["result"], JSON.parse(actual.to_json))
            end
          end

          def default_args
            []
          end
        end

        include ExpectationsRunnerMethods
      RB

      Dir.glob(TEST_RUBY_LSP_FIXTURES).each do |path|
        test_name = File.basename(path, File.extname(path))

        expectations_dir = File.join(TEST_EXP_DIR, expectation_suffix)
        unless File.directory?(expectations_dir)
          raise "Expectations directory #{expectations_dir} does not exist"
        end

        expectation_glob = Dir.glob(File.join(expectations_dir, "#{test_name}.exp.{rb,json}"))
        if expectation_glob.size == 1
          expectation_path = expectation_glob.first
        elsif expectation_glob.size > 1
          raise "multiple expectations for #{test_name}"
        end

        if expectation_path && File.file?(expectation_path)
          class_eval(<<~RB, __FILE__, __LINE__ + 1)
            def test_#{expectation_suffix}__#{test_name}
              @_path = "#{path}"
              @_expectation_path = "#{expectation_path}"
              source = File.read(@_path)
              expected = File.read(@_expectation_path)
              initialize_params(expected)
              assert_expectations(source, expected)
            end
          RB
        else
          class_eval(<<~RB, __FILE__, __LINE__ + 1)
            def test_#{expectation_suffix}__#{test_name}__does_not_raise
              @_path = "#{path}"
              source = File.read(@_path)
              run_expectations(source)
            end
          RB
        end
      end

      Dir.glob(TEST_PRISM_FIXTURES).each do |path|
        class_eval(<<~RB, __FILE__, __LINE__ + 1)
          def test_#{expectation_suffix}__#{uniq_name_from_path(path)}__does_not_raise
            @_path = "#{path}"
            source = File.read(@_path)
            run_expectations(source)
          rescue RubyLsp::Requests::Support::InternalRuboCopError, RubyLsp::Requests::Formatting::Error
            skip "Fixture requires a fix from Rubocop"
          end
        RB
      end
    end

    # Ensure that the test name include path context to avoid duplicate
    # from test/fixtures/prism/test/prism/fixtures/unparser/corpus/semantic/and.txt
    # to test_fixtures_prism_test_prism_fixtures_unparser_corpus_semantic_and
    def uniq_name_from_path(path)
      path.gsub("/", "_").gsub(".txt", "")
    end
  end

  private

  def diff(expected, actual)
    res = super
    return unless res

    begin
      # If the values are JSON we want to pretty print them
      expected_obj = { "result" => expected }
      expected_obj["params"] = @__params if @__params

      actual_obj = { "result" => actual }
      actual_obj["params"] = @__params if @__params

      $stderr.puts "########## Expected ##########"
      $stderr.puts JSON.pretty_generate(expected_obj)
      $stderr.puts "##########  Actual  ##########"
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

    JSON.parse(expected_json_string)["result"]
  end

  def initialize_params(expected)
    parsed_expected = JSON.parse(expected, symbolize_names: true)
    @__params = parsed_expected[:params] || []
  end
end
