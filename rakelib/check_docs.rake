# typed: false
# frozen_string_literal: true

desc "Check if all LSP requests are documented"
task :check_docs do
  require "sorbet-runtime"
  require "language_server-protocol"
  require "syntax_tree"
  require "logger"
  require "ruby_lsp/requests/base_request"
  require "ruby_lsp/requests/support/rubocop_diagnostics_runner"
  require "ruby_lsp/requests/support/rubocop_formatting_runner"

  request_doc_files = Dir["#{Dir.pwd}/lib/ruby_lsp/requests/*.rb"]
  request_doc_files << "#{Dir.pwd}/lib/ruby_lsp/requests.rb"

  request_doc_files.each do |file|
    require(file)
    YARD.parse(file, [], Logger::Severity::FATAL)
  end

  spec_matcher = %r{\(https://microsoft.github.io/language-server-protocol/specification#.*\)}
  error_messages = RubyLsp::Requests
    .constants # rubocop:disable Sorbet/ConstantsFromStrings
    .each_with_object(Hash.new { |h, k| h[k] = [] }) do |request, errors|
    next if request == :Support

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
    elsif !%r{!\[.* demo\]\(\.\./\.\./misc/.*\.gif\)}.match?(docs)
      errors[full_name] << <<~MESSAGE
        Documentation for request handler class must contain a demonstration GIF, in the following format:

        ![Request name demo](../../misc/request_name.gif)

        See the misc/ folder for examples.
      MESSAGE
    elsif !/# Example/.match?(docs)
      errors[full_name] << <<~MESSAGE
        Documentation for request handler class must contain an example.

        # # Example
        #
        # ```ruby
        # def my_method # <-- something happens here
        # end
        # ```
      MESSAGE
    end

    supported_features = YARD::Registry.at("RubyLsp::Requests").docstring
    next if /- {#{full_name}}/.match?(supported_features)

    errors[full_name] << <<~MESSAGE
      Documentation for request handler class must be listed in the RubyLsp::Requests module documentation.
    MESSAGE
  end

  formatted_errors = error_messages.map { |name, errors| "#{name}: #{errors.join(", ")}" }

  if error_messages.any?
    puts <<~MESSAGE
      The following requests have invalid documentation:

      #{formatted_errors.join("\n")}
    MESSAGE

    exit!
  end

  puts "All requests contain valid documentation"
end
