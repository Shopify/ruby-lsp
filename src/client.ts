import { exec } from "child_process";
import { promisify } from "util";

import * as vscode from "vscode";
import {
  LanguageClientOptions,
  LanguageClient,
  ServerOptions,
} from "vscode-languageclient/node";

const asyncExec = promisify(exec);
const LSP_NAME = "Ruby LSP";

export default class Client {
  private client: LanguageClient;
  private context: vscode.ExtensionContext;
  private workingFolder: string;

  constructor(context: vscode.ExtensionContext) {
    const outputChannel = vscode.window.createOutputChannel(LSP_NAME);
    this.workingFolder = vscode.workspace.workspaceFolders![0].uri.fsPath;

    const executable = {
      command: "bundle",
      args: ["exec", "ruby-lsp"],
      options: {
        cwd: this.workingFolder,
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
    if ((await this.gemMissing()) || (await this.gemNotInstalled())) {
      return;
    }

    this.context.subscriptions.push(this.client.start());
    await this.client.onReady();
  }

  async stop() {
    await this.client.stop();
  }

  private async gemMissing(): Promise<boolean> {
    const bundledGems = await this.execInPath("bundle list");

    if (bundledGems.includes("ruby-lsp")) {
      return false;
    }

    const response = await vscode.window.showErrorMessage(
      "The Ruby LSP gem is not a part of the bundle.",
      "Run bundle add and install",
      "Cancel"
    );

    if (response === "Run bundle add and install") {
      await this.execInPath("bundle add ruby-lsp");
      await this.execInPath("bundle install");
      return false;
    }

    return true;
  }

  private async gemNotInstalled(): Promise<boolean> {
    const bundlerCheck = await this.execInPath("bundle check");

    if (bundlerCheck.includes("The Gemfile's dependencies are satisfied")) {
      return false;
    }

    const response = await vscode.window.showErrorMessage(
      "The gems in the bundle are not installed.",
      "Run bundle install",
      "Cancel"
    );

    if (response === "Run bundle install") {
      await this.execInPath("bundle install");
      return false;
    }

    return true;
  }

  private async execInPath(command: string): Promise<string> {
    const result = await asyncExec(command, {
      cwd: this.workingFolder,
    });

    return result.stdout;
  }
}
