# typed: strict
# frozen_string_literal: true

begin
  require "syntax_tree"
  require "syntax_tree/cli"
rescue LoadError
  return
end

require "singleton"

module RubyLsp
  module Requests
    module Support
      # :nodoc:
      class SyntaxTreeFormattingRunner
        extend T::Sig
        include Singleton
        include Support::FormatterRunner

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

        sig { override.params(uri: URI::Generic, document: Document).returns(T.nilable(String)) }
        def run(uri, document)
          path = uri.to_standardized_path
          return if path && @options.ignore_files.any? { |pattern| File.fnmatch?("*/#{pattern}", path) }

          SyntaxTree.format(document.source, @options.print_width, options: @options.formatter_options)
        end
      end
    end
  end
end
