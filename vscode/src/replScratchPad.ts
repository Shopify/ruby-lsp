import * as vscode from "vscode";

export class ReplScratchPad {
  private static readonly initialContent = `# Ruby REPL Scratch Pad
# Write Ruby code here with full LSP support (completions, hover, etc.)
# 
# Keyboard Shortcuts:
#   • Ctrl+Enter: Execute current line
#   • Ctrl+Shift+Enter: Execute selection or current line
#
# Tips:
#   • Full IntelliSense and hover documentation available
#   • Errors are highlighted with red underlines
#   • Executed lines show a temporary indicator
#   • Use the terminal below for command history (up/down arrows work there)
#
# Examples:

# Variables
name = "Ruby Developer"
age = 25

# String interpolation
puts "I am #{name} and I'm #{age} years old"

# Arrays
fruits = ["apple", "banana", "orange"]
fruits.each { |fruit| puts "I like #{fruit}" }

# Hash
person = { name: "Alice", age: 30, city: "New York" }
person[:occupation] = "Developer"

# Methods
def greet(name)
  "Hello, #{name}!"
end

greet("World")
`;

  private document: vscode.TextDocument | undefined;
  private editor: vscode.TextEditor | undefined;
  private decorationType: vscode.TextEditorDecorationType;
  private errorDecorationType: vscode.TextEditorDecorationType;

  constructor() {
    this.decorationType = vscode.window.createTextEditorDecorationType({
      after: {
        color: new vscode.ThemeColor("editorCodeLens.foreground"),
        fontStyle: "italic",
      },
    });

    this.errorDecorationType = vscode.window.createTextEditorDecorationType({
      textDecoration: "wavy underline red",
      after: {
        color: new vscode.ThemeColor("errorForeground"),
        fontStyle: "italic",
      },
    });
  }

  async show(): Promise<void> {
    await this.createOrReuseScratchPadDocument();
    this.editor = await this.displayDocumentInSideEditor();
    await this.setupEditorAndTerminalLayout();
  }

  dispose(): void {
    this.closeScratchPadSafely();
    this.disposeDecorationTypes();
  }

  async closeScratchPad(): Promise<void> {
    if (this.hasScratchPadDocument()) {
      await this.closeScratchPadTab();
    }
    this.clearDocumentReferences();
  }

  getCurrentLineCode(editor: vscode.TextEditor): string {
    const line = editor.document.lineAt(editor.selection.active.line);
    return line.text.trim();
  }

  getSelectionCode(editor: vscode.TextEditor): {
    code: string;
    lineNumber: number;
  } {
    if (editor.selection.isEmpty) {
      const line = editor.document.lineAt(editor.selection.active.line);
      return {
        code: line.text.trim(),
        lineNumber: line.lineNumber,
      };
    } else {
      return {
        code: editor.document.getText(editor.selection),
        lineNumber: editor.selection.end.line,
      };
    }
  }

  showExecutionSuccess(editor: vscode.TextEditor, lineNumber: number): void {
    this.addExecutedDecoration(editor, lineNumber);
    this.clearErrorDecorations(editor);
  }

  showExecutionError(
    editor: vscode.TextEditor,
    lineNumber: number,
    error: string,
  ): void {
    this.addErrorDecoration(editor, lineNumber, error);
  }

  moveCursorToNextLine(editor: vscode.TextEditor): void {
    const currentLineNumber = editor.selection.active.line;
    const nextLine = Math.min(
      currentLineNumber + 1,
      editor.document.lineCount - 1,
    );
    const newPosition = new vscode.Position(nextLine, 0);
    editor.selection = new vscode.Selection(newPosition, newPosition);
  }

  private async createOrReuseScratchPadDocument(): Promise<void> {
    if (!this.document || this.document.isClosed) {
      this.document = await vscode.workspace.openTextDocument({
        language: "ruby",
        content: ReplScratchPad.initialContent,
      });
    }
  }

  private async displayDocumentInSideEditor(): Promise<vscode.TextEditor> {
    return vscode.window.showTextDocument(this.document!, {
      viewColumn: vscode.ViewColumn.Beside,
      preserveFocus: false,
    });
  }

  private async setupEditorAndTerminalLayout(): Promise<void> {
    this.clearExistingDecorations();
    await this.focusTerminalThenEditor();
  }

  private clearExistingDecorations(): void {
    this.editor!.setDecorations(this.decorationType, []);
    this.editor!.setDecorations(this.errorDecorationType, []);
  }

  private async focusTerminalThenEditor(): Promise<void> {
    await vscode.commands.executeCommand("workbench.action.terminal.focus");
    await vscode.commands.executeCommand(
      "workbench.action.focusActiveEditorGroup",
    );
  }

  private clearErrorDecorations(editor: vscode.TextEditor): void {
    editor.setDecorations(this.errorDecorationType, []);
  }

  private closeScratchPadSafely(): void {
    this.closeScratchPad().catch(() => {});
  }

  private disposeDecorationTypes(): void {
    this.decorationType.dispose();
    this.errorDecorationType.dispose();
  }

  private hasScratchPadDocument(): boolean {
    return Boolean(this.document && !this.document.isClosed && this.editor);
  }

  private async closeScratchPadTab(): Promise<void> {
    const scratchPadTab = this.findScratchPadTab();
    if (scratchPadTab) {
      await vscode.window.tabGroups.close(scratchPadTab);
    }
  }

  private findScratchPadTab(): vscode.Tab | undefined {
    const tabs = vscode.window.tabGroups.all
      .flatMap((group) => group.tabs)
      .filter((tab) => tab.input instanceof vscode.TabInputText);

    return tabs.find((tab) => {
      const input = tab.input as vscode.TabInputText;
      return input.uri.toString() === this.document?.uri.toString();
    });
  }

  private clearDocumentReferences(): void {
    this.document = undefined;
    this.editor = undefined;
  }

  private addExecutedDecoration(editor: vscode.TextEditor, line: number): void {
    const decorations = [
      {
        range: new vscode.Range(
          line,
          Number.MAX_SAFE_INTEGER,
          line,
          Number.MAX_SAFE_INTEGER,
        ),
        renderOptions: {
          after: {
            contentText: " ✓ executed",
            color: new vscode.ThemeColor("testing.iconPassed"),
          },
        },
      },
    ];

    editor.setDecorations(this.decorationType, decorations);
    this.scheduleDecorationsRemoval(editor, this.decorationType);
  }

  private addErrorDecoration(
    editor: vscode.TextEditor,
    line: number,
    error: string,
  ): void {
    const decorations = [
      {
        range: new vscode.Range(line, 0, line, Number.MAX_SAFE_INTEGER),
        renderOptions: {
          after: {
            contentText: ` ✗ ${error}`,
          },
        },
      },
    ];

    editor.setDecorations(this.errorDecorationType, decorations);
    this.scheduleDecorationsRemoval(editor, this.errorDecorationType);
  }

  private scheduleDecorationsRemoval(
    editor: vscode.TextEditor,
    decorationType: vscode.TextEditorDecorationType,
  ): void {
    setTimeout(() => {
      editor.setDecorations(decorationType, []);
    }, this.feedbackDuration);
  }

  private get feedbackDuration(): number {
    const config = vscode.workspace.getConfiguration("rubyLsp.replSettings");
    return config.get<number>("executionFeedbackDuration")!;
  }
}
