import fs from "fs/promises";

import * as vscode from "vscode";
import { CodeLens, State } from "vscode-languageclient/node";

import { Ruby } from "./ruby";
import { Telemetry } from "./telemetry";
import Client from "./client";
import {
  asyncExec,
  LOG_CHANNEL,
  WorkspaceInterface,
  STATUS_EMITTER,
  debounce,
} from "./common";
import { WorkspaceChannel } from "./workspaceChannel";

export class Workspace implements WorkspaceInterface {
  public lspClient?: Client;
  public readonly ruby: Ruby;
  public readonly createTestItems: (response: CodeLens[]) => void;
  public readonly workspaceFolder: vscode.WorkspaceFolder;
  private readonly context: vscode.ExtensionContext;
  private readonly telemetry: Telemetry;
  private readonly outputChannel: WorkspaceChannel;
  private needsRestart = false;
  #rebaseInProgress = false;
  #error = false;

  constructor(
    context: vscode.ExtensionContext,
    workspaceFolder: vscode.WorkspaceFolder,
    telemetry: Telemetry,
    createTestItems: (response: CodeLens[]) => void,
  ) {
    this.context = context;
    this.workspaceFolder = workspaceFolder;
    this.outputChannel = new WorkspaceChannel(
      workspaceFolder.name,
      LOG_CHANNEL,
    );
    this.telemetry = telemetry;
    this.ruby = new Ruby(context, workspaceFolder, this.outputChannel);
    this.createTestItems = createTestItems;

    this.registerRestarts(context);
    this.registerRebaseWatcher(context);
  }

  async start() {
    await this.ruby.activateRuby();

    if (this.ruby.error) {
      this.error = true;
      return;
    }

    try {
      await fs.access(this.workspaceFolder.uri.fsPath, fs.constants.W_OK);
    } catch (error: any) {
      this.error = true;

      vscode.window.showErrorMessage(
        `Directory ${this.workspaceFolder.uri.fsPath} is not writable. The Ruby LSP server needs to be able to create a
        .ruby-lsp directory to function appropriately. Consider switching to a directory for which VS Code has write
        permissions`,
      );

      return;
    }

    try {
      await this.installOrUpdateServer();
    } catch (error: any) {
      this.error = true;
      vscode.window.showErrorMessage(
        `Failed to setup the bundle: ${error.message}. \
        See [Troubleshooting](https://github.com/Shopify/ruby-lsp/blob/main/TROUBLESHOOTING.md) for help`,
      );

      return;
    }

    // The `start` method can be invoked through commands - even if there's an LSP client already running. We need to
    // ensure that the existing client for this workspace has been stopped and disposed of before we create a new one
    if (this.lspClient) {
      await this.lspClient.stop();
      await this.lspClient.dispose();
    }

    this.lspClient = new Client(
      this.context,
      this.telemetry,
      this.ruby,
      this.createTestItems,
      this.workspaceFolder,
      this.outputChannel,
    );

    try {
      STATUS_EMITTER.fire(this);
      await this.lspClient.start();
      STATUS_EMITTER.fire(this);

      // If something triggered a restart while we were still booting, then now we need to perform the restart since the
      // server can now handle shutdown requests
      if (this.needsRestart) {
        this.needsRestart = false;
        await this.restart();
      }
    } catch (error: any) {
      this.error = true;
      this.outputChannel.error(`Error starting the server: ${error.message}`);
    }
  }

  async stop() {
    await this.lspClient?.stop();
  }

  async restart() {
    try {
      if (this.#rebaseInProgress) {
        return;
      }

      // If there's no client, then we can just start a new one
      if (!this.lspClient) {
        return this.start();
      }

      switch (this.lspClient.state) {
        // If the server is still starting, then it may not be ready to handle a shutdown request yet. Trying to send
        // one could lead to a hanging process. Instead we set a flag and only restart once the server finished booting
        // in `start`
        case State.Starting:
          this.needsRestart = true;
          break;
        // If the server is running, we want to stop it, dispose of the client and start a new one
        case State.Running:
          await this.stop();
          await this.lspClient.dispose();
          this.lspClient = undefined;
          await this.start();
          break;
        // If the server is already stopped, then we need to dispose it and start a new one
        case State.Stopped:
          await this.lspClient.dispose();
          this.lspClient = undefined;
          await this.start();
          break;
      }
    } catch (error: any) {
      this.error = true;
      this.outputChannel.error(`Error restarting the server: ${error.message}`);
    }
  }

  async dispose() {
    await this.lspClient?.dispose();
  }

  // Install or update the `ruby-lsp` gem globally with `gem install ruby-lsp` or `gem update ruby-lsp`. We only try to
  // update on a daily basis, not every time the server boots
  async installOrUpdateServer(): Promise<void> {
    // If there's a user configured custom bundle to run the LSP, then we do not perform auto-updates and let the user
    // manage that custom bundle themselves
    const customBundle: string = vscode.workspace
      .getConfiguration("rubyLsp")
      .get("bundleGemfile")!;

    if (customBundle.length > 0) {
      return;
    }

    const oneDayInMs = 24 * 60 * 60 * 1000;
    const lastUpdatedAt: number | undefined = this.context.workspaceState.get(
      "rubyLsp.lastGemUpdate",
    );

    const { stderr } = await asyncExec("gem list ruby-lsp 1>&2", {
      cwd: this.workspaceFolder.uri.fsPath,
      env: this.ruby.env,
    });

    // If the gem is not yet installed, install it
    if (!stderr.includes("ruby-lsp")) {
      await asyncExec("gem install ruby-lsp", {
        cwd: this.workspaceFolder.uri.fsPath,
        env: this.ruby.env,
      });

      this.context.workspaceState.update("rubyLsp.lastGemUpdate", Date.now());
      return;
    }

    // If we haven't updated the gem in the last 24 hours, update it
    if (
      lastUpdatedAt === undefined ||
      Date.now() - lastUpdatedAt > oneDayInMs
    ) {
      try {
        await asyncExec("gem update ruby-lsp", {
          cwd: this.workspaceFolder.uri.fsPath,
          env: this.ruby.env,
        });
        this.context.workspaceState.update("rubyLsp.lastGemUpdate", Date.now());
      } catch (error) {
        // If we fail to update the global installation of `ruby-lsp`, we don't want to prevent the server from starting
        this.outputChannel.error(
          `Failed to update global ruby-lsp gem: ${error}`,
        );
      }
    }
  }

  get error() {
    return this.#error;
  }

  private set error(value: boolean) {
    STATUS_EMITTER.fire(this);
    this.#error = value;
  }

  get rebaseInProgress() {
    return this.#rebaseInProgress;
  }

  private registerRestarts(context: vscode.ExtensionContext) {
    this.createRestartWatcher(context, "Gemfile.lock");
    this.createRestartWatcher(context, "gems.locked");
    this.createRestartWatcher(context, "**/.rubocop.yml");

    // If a configuration that affects the Ruby LSP has changed, update the client options using the latest
    // configuration and restart the server
    vscode.workspace.onDidChangeConfiguration(async (event) => {
      if (event.affectsConfiguration("rubyLsp")) {
        // Re-activate Ruby if the version manager changed
        if (
          event.affectsConfiguration("rubyLsp.rubyVersionManager") ||
          event.affectsConfiguration("rubyLsp.bundleGemfile") ||
          event.affectsConfiguration("rubyLsp.customRubyCommand")
        ) {
          await this.ruby.activateRuby();
        }

        await this.restart();
      }
    });
  }

  private createRestartWatcher(
    context: vscode.ExtensionContext,
    pattern: string,
  ) {
    const watcher = vscode.workspace.createFileSystemWatcher(
      new vscode.RelativePattern(this.workspaceFolder, pattern),
    );

    const debouncedRestart = debounce(this.restart.bind(this), 5000);

    context.subscriptions.push(
      watcher,
      watcher.onDidChange(debouncedRestart),
      watcher.onDidCreate(debouncedRestart),
      watcher.onDidDelete(debouncedRestart),
    );
  }

  private registerRebaseWatcher(context: vscode.ExtensionContext) {
    const parentWatcher = vscode.workspace.createFileSystemWatcher(
      new vscode.RelativePattern(
        this.workspaceFolder,
        "../.git/{rebase-merge,rebase-apply}",
      ),
    );
    const workspaceWatcher = vscode.workspace.createFileSystemWatcher(
      new vscode.RelativePattern(
        this.workspaceFolder,
        ".git/{rebase-merge,rebase-apply}",
      ),
    );

    const startRebase = () => {
      this.#rebaseInProgress = true;
    };
    const stopRebase = async () => {
      this.#rebaseInProgress = false;
      await this.restart();
    };

    context.subscriptions.push(
      workspaceWatcher,
      parentWatcher,
      // When one of the rebase files are created, we set this flag to prevent restarting during the rebase
      workspaceWatcher.onDidCreate(startRebase),
      // Once they are deleted and the rebase is complete, then we restart
      workspaceWatcher.onDidDelete(stopRebase),
    );
  }
}
