# typed: strict
# frozen_string_literal: true

$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))

require_relative "../lib/ruby_lsp/internal"
require "minitest/autorun"
require "minitest/reporters"
require "tempfile"
require "debug"

Minitest::Reporters.use!(Minitest::Reporters::DefaultReporter.new(color: true))

module Minitest
  class Test
    Minitest::Test.make_my_diffs_pretty!
  end
end
