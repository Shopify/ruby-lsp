# typed: strict
# frozen_string_literal: true

begin
  require "rubocop"
rescue LoadError
  return
end

require "cgi"
require "singleton"

module RubyLsp
  module Requests
    module Support
      # :nodoc:
      class RuboCopRunner < RuboCop::Runner
        extend T::Sig

        sig { returns(T::Array[RuboCop::Cop::Offense]) }
        attr_reader :offenses

        DEFAULT_ARGS = T.let([
          "--stderr", # Print any output to stderr so that our stdout does not get polluted
          "--force-exclusion",
          "--format",
          "RuboCop::Formatter::BaseFormatter", # Suppress any output by using the base formatter
        ].freeze, T::Array[String])

        sig { params(args: String).void }
        def initialize(*args)
          @options = T.let({}, T::Hash[Symbol, T.untyped])
          @offenses = T.let([], T::Array[RuboCop::Cop::Offense])

          args += DEFAULT_ARGS
          rubocop_options = ::RuboCop::Options.new.parse(args).first
          super(rubocop_options, ::RuboCop::ConfigStore.new)
        end

        sig { params(path: String, contents: String).void }
        def run(path, contents)
          @offenses = []
          @options[:stdin] = contents
          super([path])
        end

        sig { returns(String) }
        def formatted_source
          @options[:stdin]
        end

        private

        sig { params(_file: String, offenses: T::Array[RuboCop::Cop::Offense]).void }
        def file_finished(_file, offenses)
          @offenses = offenses
        end
      end
    end
  end
end
