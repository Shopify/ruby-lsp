import * as vscode from "vscode";
import {
  LanguageClientOptions,
  LanguageClient,
  ServerOptions,
} from "vscode-languageclient/node";

const LSP_NAME = "Ruby LSP";

export default class Client {
  private client: LanguageClient;
  private context: vscode.ExtensionContext;

  constructor(context: vscode.ExtensionContext) {
    const outputChannel = vscode.window.createOutputChannel(LSP_NAME);

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
      outputChannel,
    };

    this.client = new LanguageClient(LSP_NAME, serverOptions, clientOptions);
    this.context = context;
  }

  async start() {
    this.context.subscriptions.push(this.client.start());
    await this.client.onReady();
  }

  async stop() {
    await this.client.stop();
  }
}
