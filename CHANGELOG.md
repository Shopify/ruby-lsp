# Change Log

All notable changes to the "ruby-lsp" extension will be documented in this file.

Check [Keep a Changelog](http://keepachangelog.com/) for recommendations on how to structure this file.

## [Unreleased]

## [0.3.1]

- Resolve TODO for LSP v3.17 (https://github.com/Shopify/ruby-lsp/pull/268)
- Add dependency constraint for LSP v3.17 (https://github.com/Shopify/ruby-lsp/pull/269)
- Handle class/module declarations as a class token with declaration modifier (https://github.com/Shopify/ruby-lsp/pull/260)
- Handle required parameters in semantic highlighting (https://github.com/Shopify/ruby-lsp/pull/271)
- Add comment continuation via on type on_type_formatting (https://github.com/Shopify/ruby-lsp/pull/274)
- Make RuboCop runner use composition instead of inheritance (https://github.com/Shopify/ruby-lsp/pull/278)
- Protect worker against cancellation during popping (https://github.com/Shopify/ruby-lsp/pull/280)
- Handle formatting errors in on_error block (https://github.com/Shopify/ruby-lsp/pull/279)
- Fix on type formatting pipe completion for regular or expressions (https://github.com/Shopify/ruby-lsp/pull/282)
- Do not fail on LoadError (https://github.com/Shopify/ruby-lsp/pull/292)

## [0.3.0]
- Add on type formatting completions (https://github.com/Shopify/ruby-lsp/pull/253)
- Upgrade syntax_tree requirement to >= 3.4 (https://github.com/Shopify/ruby-lsp/pull/254)
- Show error message when there's a InfiniteCorrectionLoop exception (https://github.com/Shopify/ruby-lsp/pull/252)
- Add request cancellation (https://github.com/Shopify/ruby-lsp/pull/243)

## [0.2.0]

- Add semantic token for keyword and keyword rest params (https://github.com/Shopify/ruby-lsp/pull/142)
- Return error responses on exceptions (https://github.com/Shopify/ruby-lsp/pull/160)
- Sanitize home directory for telemetry (https://github.com/Shopify/ruby-lsp/pull/171)
- Avoid adding semantic tokens for special methods (https://github.com/Shopify/ruby-lsp/pull/162)
- Properly respect excluded files in RuboCop requests (https://github.com/Shopify/ruby-lsp/pull/173)
- Clear diagnostics when closing files (https://github.com/Shopify/ruby-lsp/pull/174)
- Avoid pushing ranges for single line partial ranges (https://github.com/Shopify/ruby-lsp/pull/185)
- Change folding ranges to include closing tokens (https://github.com/Shopify/ruby-lsp/pull/181)
- Remove RuboCop dependency and fallback to SyntaxTree formatting (https://github.com/Shopify/ruby-lsp/pull/184)

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
