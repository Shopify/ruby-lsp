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
        include Support::Formatter

        #: -> void
        def initialize
          @options = begin
            opts = SyntaxTree::CLI::Options.new
            opts.parse(SyntaxTree::CLI::ConfigFile.new.arguments)
            opts
          end #: SyntaxTree::CLI::Options
        end

        # @override
        #: (URI::Generic uri, RubyDocument document) -> String?
        def run_formatting(uri, document)
          path = uri.to_standardized_path
          return if path && @options.ignore_files.any? { |pattern| File.fnmatch?("*/#{pattern}", path) }

          SyntaxTree.format(document.source, @options.print_width, options: @options.formatter_options)
        end

        # @override
        #: (URI::Generic uri, String source, Integer base_indentation) -> String?
        def run_range_formatting(uri, source, base_indentation)
          path = uri.to_standardized_path
          return if path && @options.ignore_files.any? { |pattern| File.fnmatch?("*/#{pattern}", path) }

          SyntaxTree.format(source, @options.print_width, base_indentation, options: @options.formatter_options)
        end

        # @override
        #: (URI::Generic uri, RubyDocument document) -> Array[Interface::Diagnostic]?
        def run_diagnostic(uri, document)
          nil
        end
      end
    end
  end
end
