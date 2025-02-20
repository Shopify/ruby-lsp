# typed: true
# frozen_string_literal: true

require "minitest/reporters/ruby_lsp_reporter"
Minitest::Reporters.use!(Minitest::Reporters::RubyLspReporter.new)

module RubyLsp
  VERSION = File.read(File.expand_path("../VERSION", __dir__)).strip
end

# # Temporary for verification
# if ENV["RUBY_LSP"]
# end
