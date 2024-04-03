# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"

ENV["RUBY_LSP_ENV"] = "test"

if ENV["COVERAGE"]
  require "simplecov"

  SimpleCov.start do
    T.bind(self, SimpleCov::Configuration)
    enable_coverage :branch
  end
end

$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))
$VERBOSE = nil unless ENV["VERBOSE"] || ENV["CI"]

require "ruby_lsp/internal"
require "ruby_lsp/test_helper"
require "rubocop/cop/ruby_lsp/use_language_server_aliases"
require "rubocop/cop/ruby_lsp/use_register_with_handler_method"

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
    include RubyLsp::TestHelper

    Minitest::Test.make_my_diffs_pretty!
  end
end

begin
  require "spoom/backtrace_filter/minitest"
  Minitest.backtrace_filter = Spoom::BacktraceFilter::Minitest.new
rescue LoadError
  # Tapioca (and thus Spoom) is not available on Windows
end
