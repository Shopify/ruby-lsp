import * as vscode from "vscode";

export class RBS {
  private decorationType: vscode.TextEditorDecorationType;
  private disposables: vscode.Disposable[] = [];

  constructor() {
    // Create decoration type with 50% opacity
    this.decorationType = vscode.window.createTextEditorDecorationType({
      opacity: "0.4",
    });

    // Register event handlers
    this.disposables.push(
      vscode.window.onDidChangeActiveTextEditor(() => this.updateDecorations()),
      vscode.workspace.onDidChangeTextDocument(() => this.updateDecorations()),
    );

    // Initial update
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
