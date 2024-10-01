# typed: strict
# frozen_string_literal: true

module RubyLsp
  # The path to the `static_docs` directory, where we keep long-form static documentation
  STATIC_DOCS_PATH = T.let(File.join(File.dirname(File.dirname(T.must(__dir__))), "static_docs"), String)

  # A map of keyword => short documentation to be displayed on hover or completion
  KEYWORD_DOCS = T.let(
    {
      "yield" => "Invokes the passed block with the given arguments",
    }.freeze,
    T::Hash[String, String],
  )
end
