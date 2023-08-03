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
          relative_path = Pathname.new(CGI.unescape(uri.path || uri.opaque))
            .relative_path_from(T.must(WORKSPACE_URI.path))
          return if @options.ignore_files.any? { |pattern| File.fnmatch(pattern, relative_path) }

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
