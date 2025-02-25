import * as vscode from "vscode";

// This class is used to dim RBS signatures in Ruby files
// For example, these signatures will be dimmed:
//
//   #: (String) -> (String | nil)
//   #: (String) { (String) -> boolish } -> void
//   #: return: String
//
// However, this will not be dimmed:
//
//   attr_reader :name #: String
//
export class RBS {
  private decorationType: vscode.TextEditorDecorationType;
  private disposables: vscode.Disposable[] = [];

  constructor() {
    this.decorationType = vscode.window.createTextEditorDecorationType({
      opacity: vscode.workspace
        .getConfiguration("rubyLsp")
        .get<string>("sigOpacityLevel")!,
    });

    // Register event handlers
    this.disposables.push(
      vscode.window.onDidChangeActiveTextEditor(() => this.updateDecorations()),
      vscode.workspace.onDidChangeTextDocument(() => this.updateDecorations()),
    );

    // Initial update
    this.updateDecorations();
  }

  reload() {
    const opacity = vscode.workspace
      .getConfiguration("rubyLsp")
      .get<string>("sigOpacityLevel")!;

    this.decorationType.dispose();
    this.decorationType = vscode.window.createTextEditorDecorationType({
      opacity,
    });
    this.updateDecorations();
  }

  dispose(): void {
    this.decorationType.dispose();
    this.disposables.forEach((item) => item.dispose());
  }

  private updateDecorations() {
    const editor = vscode.window.activeTextEditor;
    if (!editor || editor.document.languageId !== "ruby") {
      return;
    }

    const text = editor.document.getText();
    const decorations: vscode.DecorationOptions[] = [];
    const lines = text.split("\n");

    for (let i = 0; i < lines.length; i++) {
      const line = lines[i];
      if (line.trim().startsWith("#:")) {
        decorations.push({
          range: new vscode.Range(i, 0, i, line.length),
        });
      }
    }

    editor.setDecorations(this.decorationType, decorations);
  }
}
