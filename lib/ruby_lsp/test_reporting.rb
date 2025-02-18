# typed: strict
# frozen_string_literal: true

require "json"

module RubyLsp
  class TestReporting
    extend T::Sig

    sig { params(class_name: String, test_name: String, file: String).void }
    def before_test(class_name:, test_name:, file:)
      id = "#{class_name}##{test_name}"
      result = {
        event: "before_test",
        id: id,
        file: file,
      }
      puts result.to_json
    end

    sig { params(class_name: String, test_name: String, file: String).void }
    def after_test(class_name:, test_name:, file:)
      id = "#{class_name}##{test_name}"
      result = {
        event: "after_test",
        id: id,
        file: file,
      }
      puts result.to_json
    end

    sig { params(class_name: String, test_name: String, file: String).void }
    def record_pass(class_name:, test_name:, file:)
      id = "#{class_name}##{test_name}"
      result = {
        event: "pass",
        id: id,
        file: file,
      }
      puts result.to_json
    end

    sig do
      params(
        class_name: String,
        test_name: String,
        type: T.untyped, # TODO: what type should this be?
        message: String,
        file: String,
      ).void
    end
    def record_fail(class_name:, test_name:, type:, message:, file:)
      result = {
        event: "fail",
        type: type,
        message: message,
        class_name: class_name,
        test_name: test_name,
        file: file,
      }
      puts result.to_json
    end

    sig { params(class_name: String, test_name: String, message: T.nilable(String), file: String).void }
    def record_skip(class_name:, test_name:, message:, file:)
      result = {
        event: "skip",
        message: message,
        classname: class_name,
        file: file,
      }
      puts result.to_json
    end
  end
end
