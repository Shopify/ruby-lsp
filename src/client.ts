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
import { StatusItem, ServerCommand } from "./status";

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
  private statusItem: StatusItem;
  private outputChannel = vscode.window.createOutputChannel(LSP_NAME);

  constructor(
    context: vscode.ExtensionContext,
    telemetry: Telemetry,
    ruby: Ruby
  ) {
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
      outputChannel: this.outputChannel,
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
    this.statusItem = new StatusItem(this.context, this.ruby);
    this.registerCommands();
    this.registerAutoRestarts();
  }

  async start() {
    this.client = new LanguageClient(
      LSP_NAME,
      this.serverOptions,
      this.clientOptions
    );

    if (
      (await this.statusItem.installGems()) ||
      (await this.statusItem.addMissingGem())
    ) {
      return;
    }

    await this.statusItem.updateStatus(ServerCommand.Start);

    this.client.onTelemetry((event) =>
      this.telemetry.sendEvent({
        ...event,
        rubyVersion: this.ruby.rubyVersion,
        yjitEnabled: this.ruby.yjitEnabled,
      })
    );
    await this.client.start();
  }

  async stop(): Promise<void> {
    if (this.client) {
      await this.statusItem.updateStatus(ServerCommand.Stop);
      return this.client.stop();
    }
  }

  async restart() {
    try {
      await this.stop();
      await this.start();
    } catch (error: any) {
      this.outputChannel.appendLine(
        `Error restarting the server: ${error.message}`
      );
    }
  }

  private registerCommands() {
    this.context.subscriptions.push(
      vscode.commands.registerCommand("ruby-lsp.start", this.start.bind(this)),
      vscode.commands.registerCommand(
        "ruby-lsp.restart",
        this.restart.bind(this)
      ),
      vscode.commands.registerCommand("ruby-lsp.stop", this.stop.bind(this))
    );
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

        await this.restart();
      }
    });
  }

  private createRestartWatcher(pattern: string) {
    const watcher = vscode.workspace.createFileSystemWatcher(
      new vscode.RelativePattern(this.workingFolder, pattern)
    );
    this.context.subscriptions.push(watcher);

    watcher.onDidChange(this.restart.bind(this));
    watcher.onDidCreate(this.restart.bind(this));
    watcher.onDidDelete(this.restart.bind(this));
  }

  private listOfEnabledFeatures(): string[] {
    const configuration = vscode.workspace.getConfiguration("rubyLsp");
    const features: EnabledFeatures = configuration.get("enabledFeatures")!;
    const allFeatures = Object.keys(features);

    // If enableExperimentalFeatures is true, all features are enabled
    if (configuration.get("enableExperimentalFeatures")) {
      return allFeatures;
    }

    return allFeatures.filter((key) => features[key]);
  }

  private getEnv() {
    // eslint-disable-next-line no-process-env
    const env = { ...process.env };
    const useYjit = vscode.workspace.getConfiguration("rubyLsp").get("yjit");

    Object.keys(env).forEach((key) => {
      if (key.startsWith("RUBY_GC")) {
        delete env[key];
      }
    });

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
