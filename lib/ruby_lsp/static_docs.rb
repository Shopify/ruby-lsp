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
    "break" => "Terminates the execution of a block or loop",
    "case" => "Starts a case expression for pattern matching or multiple condition checking",
    "class" => "Defines a class",
    "def" => "Defines a method",
    "defined" => "Checks if a constant, variable or method is defined",
    "else" => "Executes the code in the else block if the condition is false",
    "ensure" => "Executes the code in the ensure block regardless of whether an exception is raised or not",
    "for" => "Iterates over a collection of elements",
    "module" => "Defines a module",
    "next" => "Skips the rest of the current iteration and moves to the next iteration of a loop or block",
    "rescue" => "Handles exceptions that occur in the code block",
    "return" => "Exits a method and returns a value",
    "undef" => "Removes a method definition from a class or module",
    "unless" => "Executes the code in the unless block if the condition is false",
    "until" => "Executes the code in the until block until the condition is true",
    "when" => "Matches a value against a pattern",
    "while" => "Executes the code in the while block while the condition is true",
    "yield" => "Invokes the passed block with the given arguments",
  }.freeze #: Hash[String, String]
end
