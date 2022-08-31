# typed: strict
# frozen_string_literal: true

require "ruby_lsp/requests/support/rubocop_runner"
return unless defined?(::RubyLsp::Requests::Support::RuboCopRunner)

require "cgi"
require "singleton"

module RubyLsp
  module Requests
    module Support
      # :nodoc:
      class RuboCopFormattingRunner
        extend T::Sig
        include Singleton

        sig { void }
        def initialize
          @runner = T.let(RuboCopRunner.new(
            "-a", # --auto-correct
          ), RuboCopRunner)
        end

        sig { params(uri: String, document: Document).returns(T.nilable(String)) }
        def run(uri, document)
          filename = CGI.unescape(URI.parse(uri).path)

          # Invoke RuboCop with just this file in `paths`
          @runner.run(filename, document.source)

          @runner.formatted_source
        end
      end
    end
  end
end
