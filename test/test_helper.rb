# typed: strict
# frozen_string_literal: true

$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))

require_relative "../lib/ruby_lsp/internal"
require "minitest/autorun"
require "minitest/reporters"
require "tempfile"
require "debug"

sorbet_paths = Gem.loaded_specs["sorbet-runtime"].full_require_paths.freeze
DEBUGGER__::CONFIG[:skip_path] = Array(DEBUGGER__::CONFIG[:skip_path]) + sorbet_paths

Minitest::Reporters.use!(Minitest::Reporters::DefaultReporter.new(color: true))

module Minitest
  class Test
    Minitest::Test.make_my_diffs_pretty!
  end
end
