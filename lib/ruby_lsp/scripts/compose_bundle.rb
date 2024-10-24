# typed: true
# frozen_string_literal: true

def compose(raw_initialize)
  require "ruby_lsp/setup_bundler"
  require "json"
  require "uri"
  require "core_ext/uri"

  initialize_request = JSON.parse(raw_initialize, symbolize_names: true)
  workspace_uri = initialize_request.dig(:params, :workspaceFolders, 0, :uri)
  workspace_path = workspace_uri && URI(workspace_uri).to_standardized_path
  workspace_path ||= Dir.pwd

  env = RubyLsp::SetupBundler.new(workspace_path, launcher: true).setup!
  File.write(File.join(".ruby-lsp", "bundle_gemfile"), env["BUNDLE_GEMFILE"])
  File.write(File.join(".ruby-lsp", "locked_bundler_version"), env["BUNDLER_VERSION"]) if env["BUNDLER_VERSION"]
end
