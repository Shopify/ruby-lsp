# typed: strict
# frozen_string_literal: true

begin
  require "rubocop"
rescue LoadError
  return
end

begin
  gem("rubocop", ">= 1.4.0")
rescue LoadError
  raise StandardError, "Incompatible RuboCop version. Ruby LSP requires >= 1.4.0"
end

module RubyLsp
  module Requests
    module Support
      # :nodoc:
      class RuboCopRunner < RuboCop::Runner
        extend T::Sig

        class ConfigurationError < StandardError; end

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
          @errors = T.let([], T::Array[String])
          @warnings = T.let([], T::Array[String])

          args += DEFAULT_ARGS
          rubocop_options = ::RuboCop::Options.new.parse(args).first
          config_store = ::RuboCop::ConfigStore.new

          super(rubocop_options, config_store)
        end

        sig { params(path: String, contents: String).void }
        def run(path, contents)
          # Clear Runner state between runs since we get a single instance of this class
          # on every use site.
          @errors = []
          @warnings = []
          @offenses = []
          @options[:stdin] = contents

          super([path])
        rescue RuboCop::Runner::InfiniteCorrectionLoop => error
          raise Formatting::Error, error.message
        rescue RuboCop::ValidationError => error
          raise ConfigurationError, error.message
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
