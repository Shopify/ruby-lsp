# typed: strict
# frozen_string_literal: true

# If YARP is in the bundle, we have to remove it from the $LOAD_PATH because it contains a default export named `prism`
# that will conflict with the actual Prism gem
yarp_require_paths = Gem.loaded_specs["yarp"]&.full_require_paths
$LOAD_PATH.delete_if { |path| yarp_require_paths.include?(path) } if yarp_require_paths

# Set Bundler's UI level to silent as soon as possible to prevent any prints to STDOUT
require "bundler"
Bundler.ui.level = :silent

require "json"
require "uri"
require "cgi/escape"
if Gem::Version.new(RUBY_VERSION) < Gem::Version.new("3.5")
  # Just requiring `cgi/escape` leaves CGI.unescape broken on older rubies
  # Some background on why this is necessary: https://bugs.ruby-lang.org/issues/21258
  require "cgi/util"
end
require "set"
require "strscan"
require "prism"
require "prism/visitor"
require "language_server-protocol"
require "rbs"
require "fileutils"
require "open3"
require "securerandom"
require "shellwords"
require "set"

require "ruby-lsp"
require "ruby_lsp/base_server"
require "ruby_indexer/ruby_indexer"
require "ruby_lsp/utils"
require "ruby_lsp/static_docs"
require "ruby_lsp/scope"
require "ruby_lsp/client_capabilities"
require "ruby_lsp/global_state"
require "ruby_lsp/server"
require "ruby_lsp/type_inferrer"
require "ruby_lsp/node_context"
require "ruby_lsp/document"
require "ruby_lsp/ruby_document"
require "ruby_lsp/erb_document"
require "ruby_lsp/rbs_document"
require "ruby_lsp/store"
require "ruby_lsp/addon"

# Response builders
require "ruby_lsp/response_builders/response_builder"
require "ruby_lsp/response_builders/collection_response_builder"
require "ruby_lsp/response_builders/document_symbol"
require "ruby_lsp/response_builders/hover"
require "ruby_lsp/response_builders/semantic_highlighting"
require "ruby_lsp/response_builders/signature_help"
require "ruby_lsp/response_builders/test_collection"

# Request support
require "ruby_lsp/requests/support/selection_range"
require "ruby_lsp/requests/support/annotation"
require "ruby_lsp/requests/support/sorbet"
require "ruby_lsp/requests/support/common"
require "ruby_lsp/requests/support/formatter"
require "ruby_lsp/requests/support/rubocop_runner"
require "ruby_lsp/requests/support/rubocop_formatter"
require "ruby_lsp/requests/support/syntax_tree_formatter"
require "ruby_lsp/requests/support/test_item"

# Requests
require "ruby_lsp/requests/request"
require "ruby_lsp/requests/code_action_resolve"
require "ruby_lsp/requests/code_actions"
require "ruby_lsp/requests/code_lens"
require "ruby_lsp/requests/completion_resolve"
require "ruby_lsp/requests/completion"
require "ruby_lsp/requests/definition"
require "ruby_lsp/requests/diagnostics"
require "ruby_lsp/requests/discover_tests"
require "ruby_lsp/requests/document_highlight"
require "ruby_lsp/requests/document_link"
require "ruby_lsp/requests/document_symbol"
require "ruby_lsp/requests/folding_ranges"
require "ruby_lsp/requests/formatting"
require "ruby_lsp/requests/go_to_relevant_file"
require "ruby_lsp/requests/hover"
require "ruby_lsp/requests/inlay_hints"
require "ruby_lsp/requests/on_type_formatting"
require "ruby_lsp/requests/prepare_type_hierarchy"
require "ruby_lsp/requests/prepare_rename"
require "ruby_lsp/requests/range_formatting"
require "ruby_lsp/requests/references"
require "ruby_lsp/requests/rename"
require "ruby_lsp/requests/selection_ranges"
require "ruby_lsp/requests/semantic_highlighting"
require "ruby_lsp/requests/show_syntax_tree"
require "ruby_lsp/requests/signature_help"
require "ruby_lsp/requests/type_hierarchy_supertypes"
require "ruby_lsp/requests/workspace_symbol"
