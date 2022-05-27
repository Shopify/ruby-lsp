# frozen_string_literal: true

$rubocop_exist = true
begin
  require "rubocop"
rescue
  return
end
require "cgi"

module RubyLsp
  module Requests
    module Support
      # :nodoc:
      class RuboCopRunner < RuboCop::Runner
        COMMON_RUBOCOP_FLAGS = [
          "--stderr", # Print any output to stderr so that our stdout does not get polluted
          "--format",
          "RuboCop::Formatter::BaseFormatter", # Suppress any output by using the base formatter
        ].freeze

        attr_reader :file, :text, :offenses, :formatted_text

        def initialize(uri, document, extra_flags = [])
          @file = CGI.unescape(URI.parse(uri).path)
          @document = document
          @text = document.source
          @uri = uri

          super(
            ::RuboCop::Options.new.parse(COMMON_RUBOCOP_FLAGS + extra_flags).first,
            ::RuboCop::ConfigStore.new
          )
        end

        def run
          # We communicate with Rubocop via stdin
          @options[:stdin] = text

          # Invoke the actual run method with just this file in `paths`
          super([file])

          @formatted_text = @options[:stdin] # Rubocop applies the corrections on stdin
        end

        private

        def file_finished(_file, offenses)
          @offenses = offenses
        end
      end
    end
  end
end
