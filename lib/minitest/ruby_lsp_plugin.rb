# typed: false # rubocop:disable Sorbet/StrictSigil
# frozen_string_literal: true

require "json"
require "minitest"

module Minitest
  class RubyLspReporter < Reporter
    def prerecord(klass, name)
      @id = "#{klass.name}##{name}"
      io.puts JSON.generate(event: "start", id: @id)
      io.flush
    end

    def record(result)
      if result.failures.any?
        message = result.failures.map { |f| "#{f.class.name}: #{f.message}" }.join("\n")
        io.puts JSON.generate(event: "fail", id: @id, message: message)
      else
        io.puts JSON.generate(event: "pass", id: @id)
      end
      io.flush
    end
  end

  class << self
    def plugin_ruby_lsp_options(opts, options)
      opts.on("--ruby-lsp", "Outputs structured JSON for Ruby LSP") do
        options[:ruby_lsp] = true
      end
    end

    def plugin_ruby_lsp_init(options)
      reporter.reporters = [RubyLspReporter.new($stdout)] if options[:ruby_lsp]
    end
  end
end
