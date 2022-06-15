# Change Log

All notable changes to the "ruby-lsp" extension will be documented in this file.

Check [Keep a Changelog](http://keepachangelog.com/) for recommendations on how to structure this file.

## [Unreleased]

## [0.1.0]

- Implement token modifiers in SemanticTokenEncoder ([#112](https://github.com/Shopify/ruby-lsp/pull/112))
- Add semantic token for name in a method definition ([#133](https://github.com/Shopify/ruby-lsp/pull/133))
- Add semantic highighting for def endless and singleton method names ([#134](https://github.com/Shopify/ruby-lsp/pull/134))
- Add semantic token for keyword self ([#137](https://github.com/Shopify/ruby-lsp/pull/137))
- Add semantic token for constants ([#138](https://github.com/Shopify/ruby-lsp/pull/138))
- Improve error handling + fix formatting hanging issue ([#149](https://github.com/Shopify/ruby-lsp/pull/149))
- Set the minimum syntax_tree version to 2.4 ([#151](https://github.com/Shopify/ruby-lsp/pull/151))

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
