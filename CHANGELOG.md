# Change Log

All notable changes to the "ruby-lsp" extension will be documented in this file.

Check [Keep a Changelog](http://keepachangelog.com/) for recommendations on how to structure this file.

## [Unreleased]

## [0.0.4]

- Add basic document highlight (https://github.com/Shopify/ruby-lsp/pull/91)
- Add error telemetry (https://github.com/Shopify/ruby-lsp/pull/100)
- Always push telemetry events from the server (https://github.com/Shopify/ruby-lsp/pull/109)
- Fix multibyte character handling (https://github.com/Shopify/ruby-lsp/pull/122)
- Add Sorbet to the Ruby LSP (https://github.com/Shopify/ruby-lsp/pull/119, https://github.com/Shopify/ruby-lsp/pull/123)

## [0.0.3]

- Fixed code actions return hanging
- Moved to incremental text synchronization
- Added syntax error resiliency

## [0.0.2]

- Alpha release including
    - RuboCop formatting, diagnostics and quick fixes
    - Folding ranges
    - Initial semantic highlighting
    - Document symbols
