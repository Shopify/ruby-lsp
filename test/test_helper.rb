# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"

if ENV["COVERAGE"]
  require "simplecov"

  SimpleCov.start do
    T.bind(self, SimpleCov::Configuration)
    enable_coverage :branch
  end
end

$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))
$VERBOSE = nil unless ENV["VERBOSE"] || ENV["CI"]

require_relative "../lib/ruby_lsp/internal"
require_relative "../lib/rubocop/cop/ruby_lsp/use_language_server_aliases"
require_relative "../lib/rubocop/cop/ruby_lsp/use_register_with_handler_method"

require "minitest/autorun"
require "minitest/reporters"
require "tempfile"
require "debug"
require "mocha/minitest"

SORBET_PATHS = T.let(Gem.loaded_specs["sorbet-runtime"].full_require_paths.freeze, T::Array[String])
DEBUGGER__::CONFIG[:skip_path] = Array(DEBUGGER__::CONFIG[:skip_path]) + SORBET_PATHS

minitest_reporter = if ENV["SPEC_REPORTER"]
  Minitest::Reporters::SpecReporter.new(color: true)
else
  Minitest::Reporters::DefaultReporter.new(color: true)
end
Minitest::Reporters.use!(minitest_reporter)

module Minitest
  class Test
    extend T::Sig

    Minitest::Test.make_my_diffs_pretty!

    sig { void }
    def stub_no_typechecker
      RubyLsp::DependencyDetector.instance.stubs(:typechecker).returns(false)
    end
  end
end

begin
  require "spoom/backtrace_filter/minitest"
  Minitest.backtrace_filter = Spoom::BacktraceFilter::Minitest.new
rescue LoadError
  # Tapioca (and thus Spoom) is not available on Windows
end

module RubyLsp
  module Requests
    module Support
      # The RuboCop runner catches interrupts to show a nicer exit message to users.
      # This prevents the Interrupt from reaching minitest to stop execution.
      module ReraiseInterrupt
        extend T::Sig
        extend T::Helpers

        requires_ancestor { RubyLsp::Requests::Support::RuboCopRunner }

        sig { params(path: String, contents: String).void }
        def run(path, contents)
          super
          raise Interrupt if aborting?
        end
      end
    end
  end
end

RubyLsp::Requests::Support::RuboCopRunner.prepend(RubyLsp::Requests::Support::ReraiseInterrupt)
