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

### Experiment 1: Cache GlobalState at class level (KEPT)
- Changed `ExpectationsTestRunner#setup` to share GlobalState across tests in same class
- **Impact alone**: negligible (~0s saved) — GlobalState.new is only ~2ms
- But enables experiment 1b below

### Experiment 1b: Cache RuboCopFormatter at class level (KEPT)
- `FormattingExpectationsTest` and `DiagnosticsExpectationsTest` were creating new `RuboCopFormatter` (which creates 2 `RuboCopRunner` instances each) for every test
- Cached at class level since runners are designed for reuse
- **Impact**: 454s → 301s (**153s saved, 33.8%**)

### Experiment 2: Skip addon loading in expectation tests (KEPT)
- `with_server(load_addons: true)` costs ~103ms per call vs ~2ms without
- RuboCop addon activation/deactivation per test was the main cost
- Definition and Hover expectation `run_expectations` don't need addons
- **Impact**: 301s → 217s (**84s saved, 27.9%**)

### Micro-benchmarks (informational)
- Server.new + shutdown: 1.72ms (fast)
- GlobalState.new: 2.1ms (fast)
- with_server(load_addons: true): 104.84ms (slow due to addon loading)
- with_server(load_addons: false): 2.19ms (fast)
- RuboCopFormatter.new: ~50ms (2 RuboCopRunner creations)
- Bundler.default_gemfile: 1.66ms (not a bottleneck)

### Current bottlenecks (post-optimization)
- SetupBundlerTest: 102s (off-limits, subprocess `bundle install`)
- IntegrationTest: 40s (off-limits, subprocess spawning)
- FormattingExpectationsTest: 19s (actual RuboCop work on 1176 fixtures)
- ServerTest: 17s (59 tests testing server message processing)
- DefinitionExpectationsTest: 15s (with_server per test, already skip addons)
- DiagnosticsExpectationsTest: 8s (actual RuboCop work)
- CommonTest: 4.5s (indexes entire workspace in 1 test)
