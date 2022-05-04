import { exec } from "child_process";
import { promisify } from "util";

import * as vscode from "vscode";
import {
  LanguageClientOptions,
  LanguageClient,
  ServerOptions,
  Executable,
  RevealOutputChannelOn,
} from "vscode-languageclient/node";

import { Telemetry } from "./telemetry";

const asyncExec = promisify(exec);
const LSP_NAME = "Ruby LSP";

interface EnabledFeatures {
  [key: string]: boolean;
  documentSymbols: boolean;
  foldingRanges: boolean;
  semanticHighlighting: boolean;
  formatting: boolean;
  diagnostics: boolean;
  codeActions: boolean;
}

export default class Client {
  private client: LanguageClient | undefined;
  private context: vscode.ExtensionContext;
  private workingFolder: string;
  private serverOptions: ServerOptions;
  private clientOptions: LanguageClientOptions;
  private telemetry: Telemetry;

  constructor(context: vscode.ExtensionContext, telemetry: Telemetry) {
    const outputChannel = vscode.window.createOutputChannel(LSP_NAME);
    this.workingFolder = vscode.workspace.workspaceFolders![0].uri.fsPath;
    this.telemetry = telemetry;

    const executable: Executable = {
      command: "bundle",
      args: ["exec", "ruby-lsp"],
      options: {
        cwd: this.workingFolder,
      },
    };

    this.serverOptions = {
      run: executable,
      debug: executable,
    };

    this.clientOptions = {
      documentSelector: [{ scheme: "file", language: "ruby" }],
      diagnosticCollectionName: LSP_NAME,
      outputChannel,
      revealOutputChannelOn: RevealOutputChannelOn.Never,
      initializationOptions: {
        enabledFeatures: this.listOfEnabledFeatures(),
        telemetryEnabled: telemetry.enabled(),
      },
    };

    this.context = context;
    this.registerCommands();
    this.registerAutoRestarts();
  }

  async start() {
    if ((await this.gemMissing()) || (await this.gemNotInstalled())) {
      return;
    }

    this.client = new LanguageClient(
      LSP_NAME,
      this.serverOptions,
      this.clientOptions
    );

    if (this.telemetry.enabled()) {
      this.client.onTelemetry(this.telemetry.sendEvent.bind(this.telemetry));
    }

    this.context.subscriptions.push(this.client.start());
    await this.client.onReady();
  }

  async stop() {
    if (this.client) {
      await this.client.stop();
    }
  }

  async restart() {
    await this.stop();
    await this.start();
  }

  private registerCommands() {
    this.context.subscriptions.push(
      vscode.commands.registerCommand("ruby-lsp.start", () => this.start()),
      vscode.commands.registerCommand("ruby-lsp.restart", () => this.restart()),
      vscode.commands.registerCommand("ruby-lsp.stop", () => this.stop())
    );
  }

  private async gemMissing(): Promise<boolean> {
    const bundledGems = await this.execInPath("bundle list");

    if (bundledGems.includes("ruby-lsp")) {
      return false;
    }

    if (this.context.workspaceState.get("ruby-lsp.cancelledBundleAdd")) {
      return true;
    }

    const response = await vscode.window.showErrorMessage(
      "The Ruby LSP gem is not a part of the bundle.",
      "Run bundle add and install",
      "Cancel"
    );

    if (response === "Run bundle add and install") {
      await this.execInPath("bundle add ruby-lsp --group=development");
      await this.execInPath("bundle install");
      return false;
    }

    this.context.workspaceState.update("ruby-lsp.cancelledBundleAdd", true);
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

  private registerAutoRestarts() {
    this.createRestartWatcher("Gemfile.lock");

    // If a configuration that affects the Ruby LSP has changed, update the client options using the latest
    // configuration and restart the server
    vscode.workspace.onDidChangeConfiguration((event) => {
      if (event.affectsConfiguration("rubyLsp")) {
        this.clientOptions.initializationOptions.enabledFeatures =
          this.listOfEnabledFeatures();

        this.restart();
      }
    });
  }

  private createRestartWatcher(pattern: string) {
    const watcher = vscode.workspace.createFileSystemWatcher(
      new vscode.RelativePattern(this.workingFolder, pattern)
    );
    this.context.subscriptions.push(watcher);

    watcher.onDidChange(() => this.restart());
    watcher.onDidCreate(() => this.restart());
    watcher.onDidDelete(() => this.restart());
  }

  private listOfEnabledFeatures(): string[] {
    const features: EnabledFeatures = vscode.workspace
      .getConfiguration("rubyLsp")
      .get("enabledFeatures")!;

    return Object.keys(features).filter((key) => features[key]);
  }
}
