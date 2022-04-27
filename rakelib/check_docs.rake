# frozen_string_literal: true

require "language_server-protocol"
require "syntax_tree"
require "yard"
require "logger"
require "ruby_lsp/requests/base_request"
require "ruby_lsp/requests/rubocop_request"

desc "Check if all LSP requests are documented"
task :check_docs do
  Dir["#{Dir.pwd}/lib/ruby_lsp/requests/*.rb"].each do |file|
    require(file)
    YARD.parse(file, [], Logger::Severity::FATAL)
  end

  spec_matcher = %r{{Spec}\[https://microsoft.github.io/language-server-protocol/specification#.*\]}
  error_messages = RubyLsp::Requests.constants.each_with_object(Hash.new { |h, k| h[k] = [] }) do |request, errors|
    full_name = "RubyLsp::Requests::#{request}"
    docs = YARD::Registry.at(full_name).docstring
    next if /:nodoc:/.match?(docs)

    if docs.empty?
      errors[full_name] << "missing documentation"
    elsif !spec_matcher.match?(docs)
      errors[full_name] << "missing spec link"
    elsif !/\= Example/.match?(docs)
      errors[full_name] << "missing example"
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
