# typed: strict
# frozen_string_literal: true

require "rubocop"
require "cgi"
require "singleton"

module RubyLsp
  module Requests
    module Support
      # :nodoc:
      class RuboCopDiagnosticsRunner < RuboCop::Runner
        extend T::Sig
        include Singleton

        sig { void }
        def initialize
          @options = T.let({}, T::Hash[Symbol, T.untyped])
          @uri = T.let(nil, T.nilable(String))
          @diagnostics = T.let([], T::Array[Support::RuboCopDiagnostic])

          super(
            ::RuboCop::Options.new.parse([
              "--stderr", # Print any output to stderr so that our stdout does not get polluted
              "--force-exclusion",
              "--format",
              "RuboCop::Formatter::BaseFormatter", # Suppress any output by using the base formatter
            ]).first,
            ::RuboCop::ConfigStore.new
          )
        end

        sig { params(uri: String, document: Document).returns(T::Array[Support::RuboCopDiagnostic]) }
        def run(uri, document)
          @uri = uri

          file = CGI.unescape(URI.parse(uri).path)
          # We communicate with Rubocop via stdin
          @options[:stdin] = document.source

          # Invoke RuboCop with just this file in `paths`
          process_file(file)
          @diagnostics
        end

        private

        sig { params(_file: String, offenses: T::Array[RuboCop::Cop::Offense]).void }
        def file_finished(_file, offenses)
          @diagnostics = offenses.map { |offense| Support::RuboCopDiagnostic.new(offense, T.must(@uri)) }
        end
      end
    end
  end
end
