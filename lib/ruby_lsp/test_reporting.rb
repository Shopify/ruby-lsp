# typed: strict
# frozen_string_literal: true

require "json"

module RubyLsp
  class TestReporter
    extend T::Sig

    sig { params(io: IO).void }
    def initialize(io: $stdout)
      @io = io
    end

    sig { params(id: String, file: String).void }
    def before_test(id:, file:)
      result = {
        event: "before_test",
        id: id,
        file: file,
      }
      io.puts result.to_json
    end

    sig { params(id: String, file: String).void }
    def after_test(id:, file:)
      result = {
        event: "after_test",
        id: id,
        file: file,
      }
      io.puts result.to_json
    end

    sig { params(id: String, file: String).void }
    def record_pass(id:, file:)
      result = {
        event: "pass",
        id: id,
        file: file,
      }
      io.puts result.to_json
    end

    sig do
      params(
        id: String,
        type: T.untyped, # TODO: what type should this be?
        message: String,
        file: String,
      ).void
    end
    def record_fail(id:, type:, message:, file:)
      result = {
        event: "fail",
        type: type,
        message: message,
        id: id,
        file: file,
      }
      io.puts result.to_json
    end

    sig { params(id: String, message: T.nilable(String), file: String).void }
    def record_skip(id:, message:, file:)
      result = {
        event: "skip",
        message: message,
        id: id,
        file: file,
      }
      io.puts result.to_json
    end

    private

    sig { returns(IO) }
    attr_reader :io
  end
end
