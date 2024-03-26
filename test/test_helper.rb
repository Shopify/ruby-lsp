# typed: true
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

require_relative "../lib/ruby_lsp/internal"
require_relative "../lib/ruby_lsp/test_helper"
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
    include RubyLsp::TestHelper

    Minitest::Test.make_my_diffs_pretty!

    private

    sig do
      params(
        addon_creation_method: Symbol,
        source: String,
        block: T.proc.params(server: RubyLsp::Server).void,
      ).void
    end
    def test_addon(addon_creation_method, source:, &block)
      message_queue = Thread::Queue.new

      uri = URI::Generic.from_path(path: "/fake.rb")
      server = RubyLsp::Server.new(test_mode: true)
      server.global_state.stubs(:typechecker).returns(false)
      server.process_message({
        method: "textDocument/didOpen",
        params: {
          textDocument: {
            uri: uri,
            text: source,
            version: 1,
          },
        },
      })
      index = server.global_state.index
      index.index_single(RubyIndexer::IndexablePath.new(nil, T.must(uri.to_standardized_path)), source)

      send(addon_creation_method)
      RubyLsp::Addon.load_addons(message_queue)

      block.call(server)
    ensure
      RubyLsp::Addon.addons.each(&:deactivate)
      RubyLsp::Addon.addon_classes.clear
      RubyLsp::Addon.addons.clear
      T.must(server).run_shutdown
      T.must(message_queue).close
    end
  end
end

begin
  require "spoom/backtrace_filter/minitest"
  Minitest.backtrace_filter = Spoom::BacktraceFilter::Minitest.new
rescue LoadError
  # Tapioca (and thus Spoom) is not available on Windows
end
