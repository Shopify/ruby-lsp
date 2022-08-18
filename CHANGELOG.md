# Change Log

All notable changes to the "ruby-lsp" extension will be documented in this file.

Check [Keep a Changelog](http://keepachangelog.com/) for recommendations on how to structure this file.

## [Unreleased]

## [0.2.3]

- Resolve generic source URIs for jump to gem source (https://github.com/Shopify/ruby-lsp/pull/237)

## [0.2.2]

- Support document links (https://github.com/Shopify/ruby-lsp/pull/195)
- Avoid returning on request blocks (https://github.com/Shopify/ruby-lsp/pull/232)
- Better specify gemspec files (https://github.com/Shopify/ruby-lsp/pull/233)
- Include Kernel instance methods as special methods for semantic highlighting (https://github.com/Shopify/ruby-lsp/pull/231)
- Fix call processing when message is a :call symbol literal (https://github.com/Shopify/ruby-lsp/pull/236)
- Alert users about non auto-correctable diagnostics (https://github.com/Shopify/ruby-lsp/pull/230)
- Let clients pull diagnostics instead of pushing on edits (https://github.com/Shopify/ruby-lsp/pull/242)

## [0.2.1]

- Implement the exit lifecycle request (https://github.com/Shopify/ruby-lsp/pull/198)
- Remove the Sorbet runtime from the gem's default load path (https://github.com/Shopify/ruby-lsp/pull/214)
- Return nil if the document is already formatted (https://github.com/Shopify/ruby-lsp/pull/216)
- Handle nameless keyword rest parameters in semantic highlighting (https://github.com/Shopify/ruby-lsp/pull/222)
- Display a warning on invalid RuboCop configuration (https://github.com/Shopify/ruby-lsp/pull/226)
- Centralize request handling logic in server.rb (https://github.com/Shopify/ruby-lsp/pull/221)
- Fix folding ranges for chained invocations involving an FCall (https://github.com/Shopify/ruby-lsp/pull/223)
- Fix handling of argument fowarding in semantic highlighting (https://github.com/Shopify/ruby-lsp/pull/228)
- Recover from initial syntax errors when opening documents (https://github.com/Shopify/ruby-lsp/pull/224)
- Highlight occurrences and definitions in document highlight (https://github.com/Shopify/ruby-lsp/pull/187)

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
