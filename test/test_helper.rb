# typed: strict
# frozen_string_literal: true

ENV["RUBY_LSP_ENV"] = "test"

$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))
$VERBOSE = nil unless ENV["VERBOSE"] || ENV["CI"]

require "ruby_lsp/internal"
require "ruby_lsp/test_helper"
require "rubocop/cop/ruby_lsp/use_language_server_aliases"
require "rubocop/cop/ruby_lsp/use_register_with_handler_method"

require "ruby_lsp/test_reporters/minitest_reporter"
require "minitest/autorun"
require "tempfile"
require "mocha/minitest"

# Define breakpoint methods without actually activating the debugger
require "debug/prelude"

module Minitest
  class Test
    include RubyLsp::TestHelper

    Minitest::Test.make_my_diffs_pretty!
  end
end
