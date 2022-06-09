# typed: strict
# frozen_string_literal: true

module RubyLsp
  VERSION = T.let(File.read(File.expand_path("../VERSION", __dir__)).strip, String)
end
