# typed: strict
# frozen_string_literal: true

# Routing conventions such as Rails' or Next.js' dynamic segments produce file names like `[id].rb`. Brackets are
# `Dir.glob` metacharacters and are percent-encoded in URIs, so this fixture keeps the expectations test runner honest
# about both.
module DynamicSegment
end
