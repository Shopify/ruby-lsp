import * as vscode from "vscode";

// This document provider is used for the `ruby-lsp://` scheme to show virtual files. For example, we use it to display
// the AST for a given Ruby file
export default class DocumentProvider
  implements vscode.TextDocumentContentProvider
{
  public provideTextDocumentContent(uri: vscode.Uri): string {
    let response = "Not a valid Ruby LSP document";

    switch (uri.path) {
      case "show-syntax-tree":
        response = uri.query;
        break;
    }

    return response;
  }
}
