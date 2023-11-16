# typed: strict
# frozen_string_literal: true

# Add your extra requires here (`bin/tapioca require` can be used to bootstrap this list)

# If YARP is in the bundle, we have to remove it from the $LOAD_PATH because it contains a default export named `prism`
# that will conflict with the actual Prism gem
yarp_require_paths = Gem.loaded_specs["yarp"]&.full_require_paths
$LOAD_PATH.delete_if { |path| yarp_require_paths.include?(path) } if yarp_require_paths

require "language_server-protocol"
require "prism"
require "prism/visitor"
require "mocha/minitest"
require "rubocop/minitest/assert_offense"
require "syntax_tree/cli"
require "spoom/backtrace_filter/minitest"
