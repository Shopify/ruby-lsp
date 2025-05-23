# typed: strict
# frozen_string_literal: true

module RubyLsp
  # This module contains all constants defined in the LSP spec in the same order as they are found in the spec. The only
  # exception is deprecated constants, which should not be used
  module Constant
    # [Spec link](https://microsoft.github.io/language-server-protocol/specification#errorCodes)
    module ErrorCodes
      PARSE_ERROR = -32700
      INVALID_REQUEST = -32600
      METHOD_NOT_FOUND = -32601
      INVALID_PARAMS = -32602
      INTERNAL_ERROR = -32603
      JSONRPC_RESERVED_ERROR_RANGE_START = -32099
      SERVER_ERROR_START = JSONRPC_RESERVED_ERROR_RANGE_START
      SERVER_NOT_INITIALIZED = -32002
      UNKNOWN_ERROR_CODE = -32001
      JSONRPC_RESERVED_ERROR_RANGE_END = -32000
      SERVER_ERROR_END = JSONRPC_RESERVED_ERROR_RANGE_END
      LSP_RESERVED_ERROR_RANGE_START = -32899

      # A request failed but it was syntactically correct, e.g the method name was known and the parameters were valid.
      # The error message should contain human readable information about why the request failed.
      REQUEST_FAILED = -32803

      # The server cancelled the request. This error code should only be used for requests that explicitly support being
      # server cancellable.
      SERVER_CANCELLED = -32802

      # The server detected that the content of a document got modified outside normal conditions. A server should NOT
      # send this error code if it detects a content change in its unprocessed messages. The result even computed on an
      # older state might still be useful for the client.
      #
      # If a client decides that a result is not of any use anymore the client should cancel the request.
      CONTENT_MODIFIED = -32801

      # The client has canceled a request and a server has detected the cancel.
      REQUEST_CANCELLED = -32800
      LSP_RESERVED_ERROR_RANGE_END = -32800
    end

    # [Spec link](https://microsoft.github.io/language-server-protocol/specification#positionEncodingKind)
    module PositionEncodingKind
      # Character offsets count UTF-8 code units (e.g bytes).
      UTF8 = "utf-8"

      # Character offsets count UTF-16 code units.
      #
      # This is the default and must always be supported by servers
      UTF16 = "utf-16"

      # Character offsets count UTF-32 code units.
      #
      # Implementation note: these are the same as Unicode code points, so this `PositionEncodingKind` may also be used
      # for an encoding-agnostic representation of character offsets.
      UTF32 = "utf-32"
    end

    # [Spec link](https://microsoft.github.io/language-server-protocol/specification#diagnosticSeverity)
    module DiagnosticSeverity
      ERROR = 1
      WARNING = 2
      INFORMATION = 3
      HINT = 4
    end

    # [Spec link](https://microsoft.github.io/language-server-protocol/specification#diagnosticTag)
    module DiagnosticTag
      # Unused or unnecessary code.
      #
      # Clients are allowed to render diagnostics with this tag faded out instead of having an error squiggle.
      UNNECESSARY = 1

      # Deprecated or obsolete code.
      #
      # Clients are allowed to rendered diagnostics with this tag strike through.
      DEPRECATED = 2
    end

    # [Spec link](https://microsoft.github.io/language-server-protocol/specification#markupContent)
    module MarkupKind
      # Plain text is supported as a content format
      PLAIN_TEXT = "plaintext"

      # Markdown is supported as a content format
      MARKDOWN = "markdown"
    end

    # [Spec link](https://microsoft.github.io/language-server-protocol/specification#resourceOperationKind)
    module ResourceOperationKind
      # Supports creating new files and folders.
      CREATE = "create"

      # Supports renaming existing files and folders.
      RENAME = "rename"

      # Supports deleting existing files and folders.
      DELETE = "delete"
    end

    # [Spec link](https://microsoft.github.io/language-server-protocol/specification#failureHandlingKind)
    module FailureHandlingKind
      # Applying the workspace change is simply aborted if one of the changes provided fails. All operations executed
      # before the failing operation stay executed.
      ABORT = "abort"

      # All operations are executed transactional. That means they either all succeed or no changes at all are applied
      # to the workspace.
      TRANSACTIONAL = "transactional"

      # If the workspace edit contains only textual file changes they are executed transactional. If resource changes
      # (create, rename or delete file) are part of the change the failure handling strategy is abort.
      TEXT_ONLY_TRANSACTIONAL = "textOnlyTransactional"

      # The client tries to undo the operations already executed. But there is no guarantee that this is succeeding.
      UNDO = "undo"
    end

    # [Spec link](https://microsoft.github.io/language-server-protocol/specification#textDocumentSyncKind)
    module TextDocumentSyncKind
      NONE = 0
      FULL = 1
      INCREMENTAL = 2
    end

    # [Spec link](https://microsoft.github.io/language-server-protocol/specification#textDocumentSaveReason)
    module TextDocumentSaveReason
      # Manually triggered, e.g. by the user pressing save, by starting debugging, or by an API call.
      MANUAL = 1

      # Automatic after a delay.
      AFTER_DELAY = 2

      # When the editor lost focus.
      FOCUS_OUT = 3
    end

    # [Spec link](https://microsoft.github.io/language-server-protocol/specification#documentHighlightKind)
    module DocumentHighlightKind
      TEXT = 1
      READ = 2
      WRITE = 3
    end

    # [Spec link](https://microsoft.github.io/language-server-protocol/specification#foldingRangeKind)
    module FoldingRangeKind
      # Folding range for a comment
      COMMENT = "comment"

      # Folding range for imports or includes
      IMPORTS = "imports"

      # Folding range for a region (e.g. `#region`)
      REGION = "region"
    end

    # [Spec link](https://microsoft.github.io/language-server-protocol/specification#symbolKind)
    module SymbolKind
      FILE = 1
      MODULE = 2
      NAMESPACE = 3
      PACKAGE = 4
      CLASS = 5
      METHOD = 6
      PROPERTY = 7
      FIELD = 8
      CONSTRUCTOR = 9
      ENUM = 10
      INTERFACE = 11
      FUNCTION = 12
      VARIABLE = 13
      CONSTANT = 14
      STRING = 15
      NUMBER = 16
      BOOLEAN = 17
      ARRAY = 18
      OBJECT = 19
      KEY = 20
      NULL = 21
      ENUM_MEMBER = 22
      STRUCT = 23
      EVENT = 24
      OPERATOR = 25
      TYPE_PARAMETER = 26
    end

    # [Spec link](https://microsoft.github.io/language-server-protocol/specification#symbolTag)
    module SymbolTag
      # Render a symbol as obsolete, usually using a strike-out.
      DEPRECATED = 1
    end

    # [Spec link](https://microsoft.github.io/language-server-protocol/specification#inlayHintKind)
    module InlayHintKind
      # An inlay hint that for a type annotation.
      TYPE = 1

      # An inlay hint that is for a parameter.
      PARAMETER = 2
    end

    # [Spec link](https://microsoft.github.io/language-server-protocol/specification#completionTriggerKind)
    module CompletionTriggerKind
      # Completion was triggered by typing an identifier (24x7 code complete), manual invocation (e.g Ctrl+Space) or via
      # API.
      INVOKED = 1

      # Completion was triggered by a trigger character specified by the `triggerCharacters` properties of the
      # `CompletionRegistrationOptions`.
      TRIGGER_CHARACTER = 2

      # Completion was re-triggered as the current completion list is incomplete.
      TRIGGER_FOR_INCOMPLETE_COMPLETIONS = 3
    end

    # [Spec link](https://microsoft.github.io/language-server-protocol/specification#insertTextFormat)
    module InsertTextFormat
      # The primary text to be inserted is treated as a plain string.
      PLAINTEXT = 1

      # The primary text to be inserted is treated as a snippet.
      #
      # A snippet can define tab stops and placeholders with `$1`, `$2` and `${3:foo}`. `$0` defines the final tab stop,
      # it defaults to the end of the snippet. Placeholders with equal identifiers are linked, that is typing in one
      # will update others too.
      SNIPPET = 2
    end

    # [Spec link](https://microsoft.github.io/language-server-protocol/specification#completionItemTag)
    module CompletionItemTag
      # Render a completion as obsolete, usually using a strike-out.
      DEPRECATED = 1
    end

    # [Spec link](https://microsoft.github.io/language-server-protocol/specification#insertTextMode)
    module InsertTextMode
      # The insertion or replace strings is taken as it is. If the value is multi line the lines below the cursor will
      # be inserted using the indentation defined in the string value.  The client will not apply any kind of
      # adjustments to the string.
      AS_IS = 1

      # The editor adjusts leading whitespace of new lines so that they match the indentation up to the cursor of the
      # line for which the item is accepted.
      #
      # Consider a line like this: <2tabs><cursor><3tabs>foo. Accepting a multi line completion item is indented using 2
      # tabs and all following lines inserted will be indented using 2 tabs as well.
      ADJUST_INDENTATION = 2
    end

    # [Spec link](https://microsoft.github.io/language-server-protocol/specification#completionItemKind)
    module CompletionItemKind
      TEXT = 1
      METHOD = 2
      FUNCTION = 3
      CONSTRUCTOR = 4
      FIELD = 5
      VARIABLE = 6
      CLASS = 7
      INTERFACE = 8
      MODULE = 9
      PROPERTY = 10
      UNIT = 11
      VALUE = 12
      ENUM = 13
      KEYWORD = 14
      SNIPPET = 15
      COLOR = 16
      FILE = 17
      REFERENCE = 18
      FOLDER = 19
      ENUM_MEMBER = 20
      CONSTANT = 21
      STRUCT = 22
      EVENT = 23
      OPERATOR = 24
      TYPE_PARAMETER = 25
    end

    # [Spec link](https://microsoft.github.io/language-server-protocol/specification#documentDiagnosticReportKind)
    module DocumentDiagnosticReportKind
      # A diagnostic report with a full set of problems.
      FULL = "full"

      # A report indicating that the last returned report is still accurate.
      UNCHANGED = "unchanged"
    end

    # [Spec link](https://microsoft.github.io/language-server-protocol/specification#signatureHelpTriggerKind)
    module SignatureHelpTriggerKind
      # Signature help was invoked manually by the user or by a command.
      INVOKED = 1

      # Signature help was triggered by a trigger character.
      TRIGGER_CHARACTER = 2

      # Signature help was triggered by the cursor moving or by the document content changing.
      CONTENT_CHANGE = 3
    end

    # [Spec link](https://microsoft.github.io/language-server-protocol/specification#codeActionKind)
    module CodeActionKind
      # Empty kind.
      EMPTY = ""

      # Base kind for quickfix actions: 'quickfix'.
      QUICK_FIX = "quickfix"

      # Base kind for refactoring actions: 'refactor'.
      REFACTOR = "refactor"

      # Base kind for refactoring extraction actions: 'refactor.extract'.
      #
      # Example extract actions:
      #
      # - Extract method
      # - Extract function
      # - Extract variable
      # - Extract interface from class
      # - ...
      REFACTOR_EXTRACT = "refactor.extract"

      # Base kind for refactoring inline actions: 'refactor.inline'.
      #
      # Example inline actions:
      #
      # - Inline function
      # - Inline variable
      # - Inline constant
      # - ...
      REFACTOR_INLINE = "refactor.inline"

      # Base kind for refactoring rewrite actions: 'refactor.rewrite'.
      #
      # Example rewrite actions:
      #
      # - Convert JavaScript function to class
      # - Add or remove parameter
      # - Encapsulate field
      # - Make method static
      # - Move method to base class
      # - ...
      REFACTOR_REWRITE = "refactor.rewrite"

      # Base kind for source actions: `source`.
      #
      # Source code actions apply to the entire file.
      SOURCE = "source"

      # Base kind for an organize imports source action:
      # `source.organizeImports`.
      SOURCE_ORGANIZE_IMPORTS = "source.organizeImports"

      # Base kind for a 'fix all' source action: `source.fixAll`.
      #
      # 'Fix all' actions automatically fix errors that have a clear fix that
      # do not require user input. They should not suppress errors or perform
      # unsafe fixes such as generating new types or classes.
      SOURCE_FIX_ALL = "source.fixAll"
    end

    # [Spec link](https://microsoft.github.io/language-server-protocol/specification#codeActionTriggerKind)
    module CodeActionTriggerKind
      # Code actions were explicitly requested by the user or by an extension.
      INVOKED = 1

      # Code actions were requested automatically.
      #
      # This typically happens when current selection in a file changes, but can also be triggered when file content
      # changes.
      AUTOMATIC = 2
    end

    # [Spec link](https://microsoft.github.io/language-server-protocol/specification#fileOperationPatternKind)
    module FileOperationPatternKind
      # The pattern matches a file only.
      FILE = "file"

      # The pattern matches a folder only.
      FOLDER = "folder"
    end

    # [Spec link](https://microsoft.github.io/language-server-protocol/specification#watchKind)
    module WatchKind
      CREATE = 1
      CHANGE = 2
      DELETE = 4
    end

    # [Spec link](https://microsoft.github.io/language-server-protocol/specification#fileChangeType)
    module FileChangeType
      CREATED = 1
      CHANGED = 2
      DELETED = 3
    end

    # [Spec link](https://microsoft.github.io/language-server-protocol/specification#messageType)
    module MessageType
      ERROR = 1
      WARNING = 2
      INFO = 3
      LOG = 4
      DEBUG = 5
    end
  end
end
