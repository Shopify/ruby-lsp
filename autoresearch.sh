#!/bin/bash
set -euo pipefail

# Quick pre-check: ensure test files exist
if [ ! -f "test/test_helper.rb" ]; then
  echo "ERROR: Not in ruby-lsp root directory"
  exit 1
fi

# Run the server test suite (same as `rake test`)
output=$(bundle exec rake test 2>&1) || true

# Extract metrics from minitest output
# Format: "Finished in 491.580254s, 37.2859 runs/s, 124.6978 assertions/s."
duration=$(echo "$output" | grep -oP 'Finished in \K[0-9.]+(?=s)')
# Format: "18329 runs, 61299 assertions, 2 failures, 0 errors, 14 skips"
stats_line=$(echo "$output" | grep -E '^[0-9]+ runs,')
test_count=$(echo "$stats_line" | grep -oP '^[0-9]+')
failures=$(echo "$stats_line" | grep -oP '[0-9]+(?= failures)')
errors=$(echo "$stats_line" | grep -oP '[0-9]+(?= errors)')

echo "METRIC test_duration=${duration}"
echo "METRIC test_count=${test_count}"
echo "METRIC failures=${failures}"
echo "METRIC errors=${errors}"
