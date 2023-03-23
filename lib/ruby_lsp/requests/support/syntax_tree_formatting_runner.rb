# typed: strict
# frozen_string_literal: true

require "syntax_tree/cli"
require "singleton"

module RubyLsp
  module Requests
    module Support
      # :nodoc:
      class SyntaxTreeFormattingRunner
        extend T::Sig
        include Singleton

        sig { void }
        def initialize
          @options =
            T.let(
              begin
                opts = SyntaxTree::CLI::Options.new
                opts.parse(SyntaxTree::CLI::ConfigFile.new.arguments)
                opts
              end,
              SyntaxTree::CLI::Options,
            )
        end

        sig { params(_uri: String, document: Document).returns(T.nilable(String)) }
        def run(_uri, document)
          SyntaxTree.format(
            document.source,
            @options.print_width,
            options: @options.formatter_options,
          )
        end
      end
    end
  end
end
