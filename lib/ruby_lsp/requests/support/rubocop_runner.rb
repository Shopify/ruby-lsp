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
          "--force-exclusion",
        ].freeze, T::Array[String])

        sig { params(args: String).void }
        def initialize(*args)
          @options = T.let({}, T::Hash[Symbol, T.untyped])
          @offenses = T.let([], T::Array[RuboCop::Cop::Offense])
          @errors = T.let([], T::Array[String])
          @warnings = T.let([], T::Array[String])

          args += DEFAULT_ARGS
          rubocop_options = ::RuboCop::Options.new.parse(args).first
          super(rubocop_options, ::RuboCop::ConfigStore.new)
        end

        sig { params(path: String, contents: String).void }
        def run(path, contents)
          @errors = []
          @warnings = []
          @offenses = []
          @options[:stdin] = contents
          capture_output { super([path]) }
          display_handled_errors
        end

        sig { returns(String) }
        def formatted_source
          @options[:stdin]
        end

        private

        sig { void }
        def display_handled_errors
          return if errors.empty?

          $stderr.puts "[RuboCop] Encountered and handled errors:"
          errors.uniq.each do |error|
            $stderr.puts "[RuboCop]   - #{error}"
          end
        end

        sig { params(_file: String, offenses: T::Array[RuboCop::Cop::Offense]).void }
        def file_finished(_file, offenses)
          @offenses = offenses
        end

        sig { params(block: T.proc.void).void }
        def capture_output(&block)
          original_verbosity = $VERBOSE
          orig_stdout = $stdout
          orig_stderr = $stderr

          $VERBOSE = nil
          $stderr = StringIO.new
          $stdout = StringIO.new

          block.call
        ensure
          $stdout = orig_stdout
          $stderr = orig_stderr
          $VERBOSE = original_verbosity
        end
      end
    end
  end
end
