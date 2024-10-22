# typed: strict
# frozen_string_literal: true

require_relative "compose_bundle"

# When this is invoked on Windows, we pass the raw initialize as an argument to this script. On other platforms, we
# invoke the compose method from inside a forked process
compose(ARGV.first)
