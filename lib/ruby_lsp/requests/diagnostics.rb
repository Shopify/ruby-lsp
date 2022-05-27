# frozen_string_literal: true

module RubyLsp
  module Requests
    # The
    # [diagnostics](https://microsoft.github.io/language-server-protocol/specification#textDocument_publishDiagnostics)
    # request informs the editor of RuboCop offenses for a given file.
    #
    # # Example
    #
    # ```ruby
    # def say_hello
    # puts "Hello" # --> diagnostics: incorrect indentantion
    # end
    # ```
    class Diagnostics
      NOOP_MIDDLEWARE = ->(diagnostics) {}.freeze
      @middlewares = []

      def self.run(uri, document)
        [].tap do |diagnostics|
          chain(uri, document).call(diagnostics)
          $stderr.puts "Sending diagnostics #{diagnostics.to_json}"
        end
      end

      def self.use(middleware)
        @middlewares << middleware
      end

      def self.chain(uri, document)
        @middlewares.reverse.reduce(NOOP_MIDDLEWARE) do |chain, middleware|
          middleware.new(chain, uri, document)
        end
      end

      use(Middleware::SyntaxError)
      use(Middleware::RuboCop)
    end
  end
end
