# typed: strict
# frozen_string_literal: true

# If YARP is in the bundle, we have to remove it from the $LOAD_PATH because it contains a default export named `prism`
# that will conflict with the actual Prism gem
yarp_require_paths = Gem.loaded_specs["yarp"]&.full_require_paths
$LOAD_PATH.delete_if { |path| yarp_require_paths.include?(path) } if yarp_require_paths

require "sorbet-runtime"
require "prism"
require "prism/visitor"
require "language_server-protocol"
require "bundler"
require "uri"
require "cgi"
require "set"

require "ruby-lsp"
require "ruby_indexer/ruby_indexer"
require "core_ext/uri"
require "ruby_lsp/utils"
require "ruby_lsp/parameter_scope"
require "ruby_lsp/server"
require "ruby_lsp/executor"
require "ruby_lsp/requests"
require "ruby_lsp/listener"
require "ruby_lsp/document"
require "ruby_lsp/ruby_document"
require "ruby_lsp/store"
require "ruby_lsp/addon"
require "ruby_lsp/requests/support/rubocop_runner"

Bundler.ui.level = :silent
