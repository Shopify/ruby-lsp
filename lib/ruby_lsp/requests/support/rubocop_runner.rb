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

if RuboCop.const_defined?(:LSP) # This condition will be removed when requiring RuboCop >= 1.61.
  RuboCop::LSP.enable
end

module RubyLsp
  module Requests
    module Support
      class InternalRuboCopError < StandardError
        extend T::Sig

        MESSAGE = <<~EOS
          An internal error occurred %s.
          Updating to a newer version of RuboCop may solve this.
          For more details, run RuboCop on the command line.
        EOS

        sig { params(rubocop_error: T.any(RuboCop::ErrorWithAnalyzedFileLocation, StandardError)).void }
        def initialize(rubocop_error)
          message = case rubocop_error
          when RuboCop::ErrorWithAnalyzedFileLocation
            format(MESSAGE, "for the #{rubocop_error.cop.name} cop")
          when StandardError
            format(MESSAGE, rubocop_error.message)
          end
          super(message)
        end
      end

      # :nodoc:
      class RuboCopRunner < RuboCop::Runner
        extend T::Sig

        class ConfigurationError < StandardError; end

        sig { returns(T::Array[RuboCop::Cop::Offense]) }
        attr_reader :offenses

        sig { returns(::RuboCop::Config) }
        attr_reader :config_for_working_directory

        DEFAULT_ARGS = T.let(
          [
            "--stderr", # Print any output to stderr so that our stdout does not get polluted
            "--force-exclusion",
            "--format",
            "RuboCop::Formatter::BaseFormatter", # Suppress any output by using the base formatter
          ],
          T::Array[String],
        )

        begin
          RuboCop::Options.new.parse(["--raise-cop-error"])
          DEFAULT_ARGS << "--raise-cop-error"
        rescue OptionParser::InvalidOption
          # older versions of RuboCop don't support this flag
        end
        DEFAULT_ARGS.freeze

        sig { params(args: String).void }
        def initialize(*args)
          @options = T.let({}, T::Hash[Symbol, T.untyped])
          @offenses = T.let([], T::Array[RuboCop::Cop::Offense])
          @errors = T.let([], T::Array[String])
          @warnings = T.let([], T::Array[String])

          args += DEFAULT_ARGS
          rubocop_options = ::RuboCop::Options.new.parse(args).first

          config_store = ::RuboCop::ConfigStore.new
          config_store.options_config = rubocop_options[:config] if rubocop_options[:config]
          @config_for_working_directory = T.let(config_store.for_pwd, ::RuboCop::Config)

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

          # RuboCop rescues interrupts and then sets the `@aborting` variable to true. We don't want them to be rescued,
          # so here we re-raise in case RuboCop received an interrupt.
          raise Interrupt if aborting?
        rescue RuboCop::Runner::InfiniteCorrectionLoop => error
          raise Formatting::Error, error.message
        rescue RuboCop::ValidationError => error
          raise ConfigurationError, error.message
        rescue StandardError => error
          raise InternalRuboCopError, error
        end

        sig { returns(String) }
        def formatted_source
          @options[:stdin]
        end

        class << self
          extend T::Sig

          sig { params(cop_name: String).returns(T.nilable(T.class_of(RuboCop::Cop::Base))) }
          def find_cop_by_name(cop_name)
            cop_registry[cop_name]&.first
          end

          private

          sig { returns(T::Hash[String, [T.class_of(RuboCop::Cop::Base)]]) }
          def cop_registry
            @cop_registry ||= T.let(
              RuboCop::Cop::Registry.global.to_h,
              T.nilable(T::Hash[String, [T.class_of(RuboCop::Cop::Base)]]),
            )
          end
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
