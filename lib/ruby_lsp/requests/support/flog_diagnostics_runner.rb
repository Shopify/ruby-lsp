# typed: strict
# frozen_string_literal: true

require "cgi"
require "singleton"

begin
  require "flog"
rescue LoadError
  return
end

module RubyLsp
  module Requests
    module Support
      # :nodoc:
      class FlogDiagnosticsRunner
        extend T::Sig
        include Singleton

        sig { void }
        def initialize
        end

        sig { params(uri: String, document: Document).returns(T::Array[Interface::Diagnostic]) }
        def run(uri, document)
          filename = CGI.unescape(URI.parse(uri).path)

          # Run flog for this file, parsing the results and generating diagnostics for each of the methods
          # that exceed the threshold
          flog = Flog.new
          flog.flog(filename)

          flog.totals.filter_map do |method_name, score|
            # TODO: make this configurable
            next if score <= 10

            location = flog.method_locations[method_name]
            next unless location

            # location is of the form filename:start_line-end_line
            filename, range = location.split(":")
            start_line, _end_line = range.split("-")
            Interface::Diagnostic.new(
              range: Interface::Range.new(
                start: Interface::Position.new(line: start_line.to_i - 1, character: 0),
                end: Interface::Position.new(line: start_line.to_i - 1, character: 0),
              ),
              severity: Constant::DiagnosticSeverity::WARNING,
              code: "Flog",
              source: "flog",
              message: "Score of #{score.round(2)} for method #{method_name}",
              data: {
                correctable: false,
              },
            )
          end
        end
      end
    end
  end
end
