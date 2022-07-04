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
      class RuboCopFormattingRunner < RuboCop::Runner
        extend T::Sig
        include Singleton

        sig { void }
        def initialize
          @options = T.let({}, T::Hash[Symbol, T.untyped])

          super(
            ::RuboCop::Options.new.parse([
              "--stderr", # Print any output to stderr so that our stdout does not get polluted
              "--force-exclusion",
              "--format",
              "RuboCop::Formatter::BaseFormatter", # Suppress any output by using the base formatter
              "-a", # --auto-correct
            ]).first,
            ::RuboCop::ConfigStore.new
          )
        end

        sig { params(uri: String, document: Document).returns(T.nilable(String)) }
        def run(uri, document)
          file = CGI.unescape(URI.parse(uri).path)
          # We communicate with Rubocop via stdin
          @options[:stdin] = document.source

          # Invoke RuboCop with just this file in `paths`
          super([file])
          @options[:stdin]
        end
      end
    end
  end
end
