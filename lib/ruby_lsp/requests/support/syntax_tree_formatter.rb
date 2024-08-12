# typed: strict
# frozen_string_literal: true

begin
  require "syntax_tree"
  require "syntax_tree/cli"
rescue LoadError
  return
end

module RubyLsp
  module Requests
    module Support
      # :nodoc:
      class SyntaxTreeFormatter
        extend T::Sig
        include Support::Formatter

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
        def run_formatting(uri, document)
          path = uri.to_standardized_path
          return if path && @options.ignore_files.any? { |pattern| File.fnmatch?("*/#{pattern}", path) }

          SyntaxTree.format(document.source, @options.print_width, options: @options.formatter_options)
        end

        sig do
          override.params(
            uri: URI::Generic,
            document: Document,
          ).returns(T.nilable(T::Array[Interface::Diagnostic]))
        end
        def run_diagnostic(uri, document)
          nil
        end
      end
    end
  end
end
