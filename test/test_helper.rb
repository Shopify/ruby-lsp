# frozen_string_literal: true

$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))

require "ruby-lsp"
require "minitest/autorun"
require "minitest/reporters"
require "tempfile"

Minitest::Reporters.use!(Minitest::Reporters::SpecReporter.new(color: true))

module Minitest
  class Test
    Minitest::Test.make_my_diffs_pretty!
  end
end
