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
import { Ruby } from "./ruby";

const asyncExec = promisify(exec);
const LSP_NAME = "Ruby LSP";

interface EnabledFeatures {
  [key: string]: boolean;
}

export default class Client {
  private client: LanguageClient | undefined;
  private context: vscode.ExtensionContext;
  private workingFolder: string;
  private serverOptions: ServerOptions;
  private clientOptions: LanguageClientOptions;
  private telemetry: Telemetry;
  private ruby: Ruby;

  constructor(
    context: vscode.ExtensionContext,
    telemetry: Telemetry,
    ruby: Ruby
  ) {
    const outputChannel = vscode.window.createOutputChannel(LSP_NAME);
    this.workingFolder = vscode.workspace.workspaceFolders![0].uri.fsPath;
    this.telemetry = telemetry;
    this.ruby = ruby;

    const env = this.getEnv();

    const executable: Executable = {
      command: "bundle",
      args: ["exec", "ruby-lsp"],
      options: {
        cwd: this.workingFolder,
        env,
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
      },
      middleware: {
        provideOnTypeFormattingEdits: async (
          document,
          position,
          ch,
          options,
          token,
          _next
        ) => {
          if (this.client) {
            const response: vscode.TextEdit[] | null =
              await this.client.sendRequest(
                "textDocument/onTypeFormatting",
                {
                  textDocument: { uri: document.uri.toString() },
                  position,
                  ch,
                  options,
                },
                token
              );

            if (!response) {
              return null;
            }

            // Find the $0 anchor to move the cursor
            const cursorPosition = response.find(
              (edit) => edit.newText === "$0"
            );

            if (!cursorPosition) {
              return response;
            }

            // Remove the edit including the $0 anchor
            response.splice(response.indexOf(cursorPosition), 1);

            const workspaceEdit = new vscode.WorkspaceEdit();
            workspaceEdit.set(document.uri, response);
            await vscode.workspace.applyEdit(workspaceEdit);

            await vscode.window.activeTextEditor!.insertSnippet(
              new vscode.SnippetString(cursorPosition.newText),
              new vscode.Selection(
                cursorPosition.range.start,
                cursorPosition.range.end
              )
            );

            return null;
          }

          return undefined;
        },
      },
    };

    this.context = context;
    this.registerCommands();
    this.registerAutoRestarts();
  }

  async start() {
    if ((await this.gemNotInstalled()) || (await this.gemMissing())) {
      return;
    }

    this.client = new LanguageClient(
      LSP_NAME,
      this.serverOptions,
      this.clientOptions
    );

    this.client.onTelemetry(this.telemetry.sendEvent.bind(this.telemetry));
    await this.client.start();
  }

  async stop(): Promise<void> {
    if (this.client) {
      return this.client.stop();
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
    const hasRubocopLsp = bundledGems.includes("rubocop-lsp");
    const hasRubyLsp = bundledGems.includes("ruby-lsp");

    if (hasRubocopLsp) {
      await vscode.window.showErrorMessage(
        "The rubocop-lsp gem has been replaced by the ruby-lsp.",
        {
          modal: true,
          detail: "Please remove the rubocop-lsp from the Gemfile",
        }
      );
    }

    if (hasRubyLsp) {
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
    let bundlerCheck: string;

    try {
      bundlerCheck = await this.execInPath("bundle check");
    } catch {
      bundlerCheck = "";
    }

    if (bundlerCheck.includes("The Gemfile's dependencies are satisfied")) {
      return false;
    }

    const response = await vscode.window.showErrorMessage(
      "The gems in the bundle are not installed.",
      "Run bundle install",
      "Cancel"
    );

    if (response === "Run bundle install") {
      await vscode.window.withProgress(
        {
          location: vscode.ProgressLocation.Notification,
          title: "Installing gems",
        },
        async (progress) => {
          try {
            await this.execInPath("bundle install");
          } catch {
            // The progress dialog can't be closed by the user, so we have to guarantee that we catch errors
            progress.report({ message: "Failed to install gems" });
          }
        }
      );

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
    this.createRestartWatcher("**/.rubocop.yml");

    // If a configuration that affects the Ruby LSP has changed, update the client options using the latest
    // configuration and restart the server
    vscode.workspace.onDidChangeConfiguration(async (event) => {
      if (event.affectsConfiguration("rubyLsp")) {
        this.clientOptions.initializationOptions.enabledFeatures =
          this.listOfEnabledFeatures();

        // Re-activate Ruby if the version manager changed
        if (event.affectsConfiguration("rubyLsp.rubyVersionManager")) {
          await this.ruby.activateRuby();
        }

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

  private getEnv() {
    // eslint-disable-next-line no-process-env
    const env = process.env;
    const useYjit = vscode.workspace.getConfiguration("rubyLsp").get("yjit");

    if (!this.ruby.rubyVersion) {
      return env;
    }

    const [major, minor, _patch] = this.ruby.rubyVersion.split(".").map(Number);

    // Enabling YJIT only provides a performance benefit on Ruby 3.2.0 and above
    if (!useYjit || !this.ruby.yjitEnabled || [major, minor] < [3, 2]) {
      return env;
    }

    // RUBYOPT may be empty or it may contain bundler paths. In the second case, we must concat to avoid accidentally
    // removing the paths from the env variable
    if (env.RUBYOPT) {
      env.RUBYOPT.concat(" --yjit");
    } else {
      env.RUBYOPT = "--yjit";
    }

    return env;
  }
}
