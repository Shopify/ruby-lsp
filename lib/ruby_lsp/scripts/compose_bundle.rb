# typed: true
# frozen_string_literal: true

def compose(raw_initialize)
  require_relative "../setup_bundler"
  require "json"
  require "uri"
  require "ruby_indexer/lib/ruby_indexer/uri"

  initialize_request = JSON.parse(raw_initialize, symbolize_names: true)
  workspace_uri = initialize_request.dig(:params, :workspaceFolders, 0, :uri)
  workspace_path = workspace_uri && URI(workspace_uri).to_standardized_path
  workspace_path ||= Dir.pwd

  env = RubyLsp::SetupBundler.new(workspace_path, launcher: true).setup!

  File.open(File.join(".ruby-lsp", "bundle_env"), "w") do |f|
    f.flock(File::LOCK_EX)
    f.write(env.map { |k, v| "#{k}=#{v}" }.join("\n"))
    f.flush
  end
end
