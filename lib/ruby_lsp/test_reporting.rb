# typed: strict
# frozen_string_literal: true

require "json"

module RubyLsp
  class TestReporting
    def before_test(class_name:)
      result = {
        event: "before_test",
        classname: class_name,
      }
      puts result.to_json
    end

    def record_pass(class_name:, file:, line:)
      result = {
        event: "pass",
        classname: class_name,
        file: file,
        line: line,
      }
      puts result.to_json
    end

    def record_fail(class_name:, type:, message:, file:, line:)
      result = {
        event: "fail",
        type: type,
        message: message,
        class_name: class_name,
        file: file,
        line: line,
      }
      puts result.to_json
    end

    def record_skip(class_name:, file:, line:)
      result = {
        event: "skip",
        classname: class_name,
        file: file,
        line: line,
      }
      puts result.to_json
    end
  end
end
