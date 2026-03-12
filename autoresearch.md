# Autoresearch: Ruby LSP Server Test Duration

## Objective
Reduce the wall-clock time of `bundle exec rake test` (the server-level test suite, ~18,329 tests).
Baseline: **~490 seconds** on macOS with Ruby 3.4.7.

The test suite uses Minitest. The Rakefile's `test` task runs `test/**/*_test.rb` excluding `test/fixtures/prism/**/*`.

## Metrics
- **Primary**: `test_duration` (seconds, lower is better) — wall-clock time reported by Minitest's "Finished in X seconds"
- **Secondary**: `test_count` (must stay >= 18329), `failures` (must stay <= 2, the 2 pre-existing nix-path failures), `errors` (must stay 0)

## How to Run
```bash
source /opt/homebrew/share/chruby/chruby.sh && chruby ruby-3.4.7 && ./autoresearch.sh
```
Outputs `METRIC name=number` lines parsed by the experiment tooling.

## Profiling Baseline (Top Slow Classes)

| Time (s) | Class | Tests | Avg (s) | Root Cause |
|----------|-------|-------|---------|------------|
| 149.84 | SetupBundlerTest | 41 | 3.7 | `bundle install` subprocess per test |
| 104.51 | FormattingExpectationsTest | 1176 | 0.09 | GlobalState + RuboCop init per test |
| 103.18 | DiagnosticsExpectationsTest | 1176 | 0.09 | GlobalState + RuboCop init per test |
| 43.56 | IntegrationTest | 18 | 2.4 | Full process spawn + bundle install |
| 18.50 | DefinitionExpectationsTest | 1221 | 0.015 | GlobalState per test |
| 17.10 | ServerTest | 59 | 0.29 | Server + threads per test |
| 8.84 | HoverExpectationsTest | 1210 | 0.007 | GlobalState per test |
| 5.64 | CommonTest | 1 | 5.64 | Entry kind iteration |

## Files in Scope

### Test infrastructure (primary targets)
- `test/test_helper.rb` — test helper loaded by all tests
- `lib/ruby_lsp/test_helper.rb` — `with_server` helper, creates Server per call
- `test/requests/support/expectations_test_runner.rb` — generates expectation tests, creates GlobalState per test

### Slow test files
- `test/setup_bundler_test.rb` — 150s, runs `bundle install` in subprocess
- `test/integration_test.rb` — 44s, spawns full LSP processes
- `test/server_test.rb` — 17s, creates Server per test

### Core objects created per-test
- `lib/ruby_lsp/global_state.rb` — GlobalState with Index, TypeInferrer, etc.
- `lib/ruby_lsp/server.rb` — Server with threads, store, global state
- `lib/ruby_indexer/lib/ruby_indexer/index.rb` — Index with prefix trees

## Off Limits
- **Do NOT change test semantics** — tests must still verify the same behavior
- **Do NOT delete or skip tests** — test_count must remain >= 18329
- **Do NOT modify production (non-test) code** to optimize tests (except if adding test-only hooks)
- **Do NOT add new gem dependencies**
- `test/fixtures/` — fixture files must not be modified
- `test/expectations/` — expectation JSON files must not be modified
- `lib/ruby_lsp/test_helper.rb` — public API used by addon authors, changes must be backward-compatible
- Integration tests and SetupBundlerTest — these intentionally test subprocess behavior

## Constraints
- All 18,329+ tests must pass (excluding 2 pre-existing nix-path failures)
- No new test failures or errors
- Changes must be safe for CI (no machine-specific hacks)
- Ruby version: 3.4.7 via chruby
- Activation: `source /opt/homebrew/share/chruby/chruby.sh && chruby ruby-3.4.7`

## What's Been Tried
(Nothing yet — this is the initial baseline.)
