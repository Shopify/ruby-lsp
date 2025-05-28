# typed: strict
# frozen_string_literal: true

module RubyLsp
  # The path to the `static_docs` directory, where we keep long-form static documentation
  STATIC_DOCS_PATH = File.join(
    File.dirname(
      File.dirname(
        __dir__, #: as !nil
      ),
    ),
    "static_docs",
  ) #: String

  # A map of keyword => short documentation to be displayed on hover or completion
  KEYWORD_DOCS = {
    "yield" => "Invokes the passed block with the given arguments",
    "case" => "Starts a case expression for pattern matching or multiple condition checking",
    "begin" => "Starts an exception handling block or ensures code is executed in order",
    "break" => "Terminates the execution of a block, loop, or method",
  }.freeze #: Hash[String, String]
end
