# typed: strict
# frozen_string_literal: true

require "rubocop"
require "cgi"

module RubyLsp
  module Requests
    # :nodoc:
    class RuboCopRequest < RuboCop::Runner
      extend T::Sig
      extend T::Helpers

      abstract!

      COMMON_RUBOCOP_FLAGS = T.let([
        "--stderr", # Print any output to stderr so that our stdout does not get polluted
        "--format",
        "RuboCop::Formatter::BaseFormatter", # Suppress any output by using the base formatter
      ].freeze, T::Array[String])

      sig { returns(String) }
      attr_reader :file

      sig { returns(String) }
      attr_reader :text

      sig { overridable.params(uri: String, document: Document).returns(T.untyped) }
      def self.run(uri, document)
        new(uri, document).run
      end

      sig { params(uri: String, document: Document).void }
      def initialize(uri, document)
        @file = T.let(CGI.unescape(URI.parse(uri).path), String)
        @document = document
        @text = T.let(document.source, String)
        @uri = uri
        @options = T.let({}, T::Hash[Symbol, T.untyped])
        @diagnostics = T.let([], T::Array[Support::RuboCopDiagnostic])

        super(
          ::RuboCop::Options.new.parse(rubocop_flags).first,
          ::RuboCop::ConfigStore.new
        )
      end

      sig { returns(T.untyped) }
      def run
        # We communicate with Rubocop via stdin
        @options[:stdin] = text

        # Invoke the actual run method with just this file in `paths`
        super([file])
      end

      private

      sig { returns(T::Array[String]) }
      def rubocop_flags
        COMMON_RUBOCOP_FLAGS
      end
    end
  end
end
