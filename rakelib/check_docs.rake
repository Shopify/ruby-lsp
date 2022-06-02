# typed: false
# frozen_string_literal: true

desc "Check if all LSP requests are documented"
task :check_docs do
  require "language_server-protocol"
  require "syntax_tree"
  require "logger"
  require "ruby_lsp/requests/base_request"
  require "ruby_lsp/requests/rubocop_request"

  Dir["#{Dir.pwd}/lib/ruby_lsp/requests/*.rb"].each do |file|
    require(file)
    YARD.parse(file, [], Logger::Severity::FATAL)
  end

  spec_matcher = %r{\(https://microsoft.github.io/language-server-protocol/specification#.*\)}
  error_messages = RubyLsp::Requests
    .constants # rubocop:disable Sorbet/ConstantsFromStrings
    .each_with_object(Hash.new { |h, k| h[k] = [] }) do |request, errors|
    full_name = "RubyLsp::Requests::#{request}"
    docs = YARD::Registry.at(full_name).docstring
    next if /:nodoc:/.match?(docs)

    if docs.empty?
      errors[full_name] << "Missing documentation for request handler class"
    elsif !spec_matcher.match?(docs)
      errors[full_name] << <<~MESSAGE
        Documentation for request handler classes must link to the official LSP specification.

        For example, if your request handles text document hover, you should add a link to
        https://microsoft.github.io/language-server-protocol/specifications/specification-current/#textDocument_hover.
      MESSAGE
    elsif !/# Example/.match?(docs)
      errors[full_name] << <<~MESSAGE
        Documentation for request handler class must contain an example.

        = Example
            def my_method # <-- something happens here
            end
      MESSAGE
    end
  end

  formatted_errors = error_messages.map { |name, errors| "#{name}: #{errors.join(", ")}" }

  if error_messages.any?
    puts <<~MESSAGE
      The following requests have invalid documentation:

      #{formatted_errors.join("\n")}
    MESSAGE

    exit!
  end
end
