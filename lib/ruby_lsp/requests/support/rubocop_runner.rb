# typed: strict
# frozen_string_literal: true

require "rubocop"
require "cgi"

module RubyLsp
  module Requests
    module Support
      # :nodoc:
      class RuboCopRunner < RuboCop::Runner
        extend T::Sig

        module CallbackHandler
          extend T::Sig
          extend T::Helpers

          interface!

          sig { abstract.params(offenses: T::Array[RuboCop::Cop::Offense]).void }
          def callback(offenses); end
        end

        class << self
          extend T::Sig

          sig { returns(RuboCopRunner) }
          def diagnostics_instance
            @diagnostics_instance = T.let(nil, T.nilable(RuboCopRunner))
            return @diagnostics_instance if @diagnostics_instance

            @diagnostics_instance = new(
              [
                "--stderr", # Print any output to stderr so that our stdout does not get polluted
                "--force-exclusion",
                "--format",
                "RuboCop::Formatter::BaseFormatter", # Suppress any output by using the base formatter
              ]
            )
          end

          sig { returns(RuboCopRunner) }
          def formatting_instance
            @formatting_instance = T.let(nil, T.nilable(RuboCopRunner))
            return @formatting_instance if @formatting_instance

            @formatting_instance = new(
              [
                "--stderr", # Print any output to stderr so that our stdout does not get polluted
                "--force-exclusion",
                "--format",
                "RuboCop::Formatter::BaseFormatter", # Suppress any output by using the base formatter
                "-a", # --auto-correct
              ]
            )
          end
        end

        sig { returns(T.nilable(String)) }
        attr_reader :text

        sig { params(rubocop_flags: T::Array[String]).void }
        def initialize(rubocop_flags)
          @text = T.let(nil, T.nilable(String))
          @options = T.let({}, T::Hash[Symbol, Object])
          @handler = T.let(nil, T.nilable(CallbackHandler))

          super(
            ::RuboCop::Options.new.parse(rubocop_flags).first,
            ::RuboCop::ConfigStore.new
          )
        end

        sig { overridable.params(uri: String, document: Document, handler: CallbackHandler).returns(Object) }
        def run(uri, document, handler)
          @handler = handler
          @text = document.source

          file = CGI.unescape(URI.parse(uri).path)
          # We communicate with Rubocop via stdin
          @options[:stdin] = text

          # Invoke the actual run method with just this file in `paths`
          super([file])
        end

        sig { returns(T.nilable(String)) }
        def stdin
          @options[:stdin]&.to_s
        end

        private

        sig { params(_file: String, offenses: T::Array[RuboCop::Cop::Offense]).void }
        def file_finished(_file, offenses)
          @handler&.callback(offenses)
        end
      end
    end
  end
end
