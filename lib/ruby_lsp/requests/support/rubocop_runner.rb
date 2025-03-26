# typed: strict
# frozen_string_literal: true

# If there's no top level Gemfile, don't load RuboCop from a global installation
begin
  Bundler.with_original_env { Bundler.default_gemfile }
rescue Bundler::GemfileNotFound
  return
end

# Ensure that RuboCop is available
begin
  require "rubocop"
rescue LoadError
  return
end

# Remember to update the version in the documentation (usage/dependency-compatibility section) if you change this
# Ensure that RuboCop is at least version 1.4.0
begin
  gem("rubocop", ">= 1.4.0")
rescue LoadError
  $stderr.puts "Incompatible RuboCop version. Ruby LSP requires >= 1.4.0"
  return
end

if RuboCop.const_defined?(:LSP) # This condition will be removed when requiring RuboCop >= 1.61.
  RuboCop::LSP.enable
end

module RubyLsp
  module Requests
    module Support
      class InternalRuboCopError < StandardError
        MESSAGE = <<~EOS
          An internal error occurred %s.
          Updating to a newer version of RuboCop may solve this.
          For more details, run RuboCop on the command line.
        EOS

        #: ((::RuboCop::ErrorWithAnalyzedFileLocation | StandardError) rubocop_error) -> void
        def initialize(rubocop_error)
          message = case rubocop_error
          when ::RuboCop::ErrorWithAnalyzedFileLocation
            format(MESSAGE, "for the #{rubocop_error.cop.name} cop")
          when StandardError
            format(MESSAGE, rubocop_error.message)
          end
          super(message)
        end
      end

      # :nodoc:
      class RuboCopRunner < ::RuboCop::Runner
        class ConfigurationError < StandardError; end

        DEFAULT_ARGS = [
          "--stderr", # Print any output to stderr so that our stdout does not get polluted
          "--force-exclusion",
          "--format",
          "RuboCop::Formatter::BaseFormatter", # Suppress any output by using the base formatter
        ] #: Array[String]

        #: Array[::RuboCop::Cop::Offense]
        attr_reader :offenses

        #: ::RuboCop::Config
        attr_reader :config_for_working_directory

        begin
          ::RuboCop::Options.new.parse(["--raise-cop-error"])
          DEFAULT_ARGS << "--raise-cop-error"
        rescue OptionParser::InvalidOption
          # older versions of RuboCop don't support this flag
        end
        DEFAULT_ARGS.freeze

        #: (*String args) -> void
        def initialize(*args)
          @options = {} #: Hash[Symbol, untyped]
          @offenses = [] #: Array[::RuboCop::Cop::Offense]
          @errors = [] #: Array[String]
          @warnings = [] #: Array[String]

          args += DEFAULT_ARGS
          rubocop_options = ::RuboCop::Options.new.parse(args).first

          config_store = ::RuboCop::ConfigStore.new
          config_store.options_config = rubocop_options[:config] if rubocop_options[:config]
          @config_for_working_directory = config_store.for_pwd #: ::RuboCop::Config

          super(rubocop_options, config_store)
        end

        #: (String path, String contents) -> void
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
        rescue ::RuboCop::Runner::InfiniteCorrectionLoop => error
          raise Formatting::Error, error.message
        rescue ::RuboCop::ValidationError => error
          raise ConfigurationError, error.message
        rescue StandardError => error
          raise InternalRuboCopError, error
        end

        #: -> String
        def formatted_source
          @options[:stdin]
        end

        class << self
          #: (String cop_name) -> singleton(::RuboCop::Cop::Base)?
          def find_cop_by_name(cop_name)
            cop_registry[cop_name]&.first
          end

          private

          #: -> Hash[String, [singleton(::RuboCop::Cop::Base)]]
          def cop_registry
            @cop_registry ||= ::RuboCop::Cop::Registry.global.to_h #: Hash[String, [singleton(::RuboCop::Cop::Base)]]?
          end
        end

        private

        #: (String _file, Array[::RuboCop::Cop::Offense] offenses) -> void
        def file_finished(_file, offenses)
          @offenses = offenses
        end
      end
    end
  end
end
