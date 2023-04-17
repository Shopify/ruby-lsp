# typed: strict
# frozen_string_literal: true

$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))
$VERBOSE = nil unless ENV["VERBOSE"] || ENV["CI"]

require_relative "../lib/ruby_lsp/internal"
require_relative "../lib/rubocop/cop/ruby_lsp/use_language_server_aliases"

require "minitest/autorun"
require "minitest/reporters"
require "tempfile"
require "debug"
require "mocha/minitest"

sorbet_paths = Gem.loaded_specs["sorbet-runtime"].full_require_paths.freeze
DEBUGGER__::CONFIG[:skip_path] = Array(DEBUGGER__::CONFIG[:skip_path]) + sorbet_paths

minitest_reporter = if ENV["SPEC_REPORTER"]
  Minitest::Reporters::SpecReporter.new(color: true)
else
  Minitest::Reporters::DefaultReporter.new(color: true)
end
Minitest::Reporters.use!(minitest_reporter)
Minitest::Test.make_my_diffs_pretty!

# Eager load the Index to avoid constant reloading issues with Sorbet
RubyLsp::Index.instance
T::Utils.run_all_sig_blocks
