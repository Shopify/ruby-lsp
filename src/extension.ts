import * as vscode from "vscode";
import {
  LanguageClientOptions,
  LanguageClient,
  ServerOptions,
} from "vscode-languageclient/node";

const LSP_NAME = "Ruby LSP";

let client: LanguageClient;

export function activate(_context: vscode.ExtensionContext) {
  const executable = {
    command: "bundle",
    args: ["exec", "ruby-lsp"],
    options: {
      cwd: vscode.workspace.workspaceFolders![0].uri.fsPath,
    },
  };

  const serverOptions: ServerOptions = {
    run: executable,
    debug: executable,
  };

  const clientOptions: LanguageClientOptions = {
    documentSelector: [{ scheme: "file", language: "ruby" }],
    diagnosticCollectionName: LSP_NAME,
  };

  client = new LanguageClient(LSP_NAME, serverOptions, clientOptions);

  client.start();
}

export function deactivate() {
  if (!client) {
    return undefined;
  }

  return client.stop();
}
