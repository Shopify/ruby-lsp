import fs from "fs/promises";
import path from "path";

import * as vscode from "vscode";
import { CodeLens } from "vscode-languageclient/node";

import { Ruby } from "./ruby";
import { Telemetry } from "./telemetry";
import Client from "./client";
import {
  asyncExec,
  LOG_CHANNEL,
  WorkspaceInterface,
  STATUS_EMITTER,
  pathExists,
} from "./common";

export class Workspace implements WorkspaceInterface {
  public lspClient?: Client;
  public readonly ruby: Ruby;
  public readonly createTestItems: (response: CodeLens[]) => void;
  public readonly workspaceFolder: vscode.WorkspaceFolder;
  private readonly context: vscode.ExtensionContext;
  private readonly telemetry: Telemetry;
  #error = false;

  constructor(
    context: vscode.ExtensionContext,
    workspaceFolder: vscode.WorkspaceFolder,
    telemetry: Telemetry,
    createTestItems: (response: CodeLens[]) => void,
  ) {
    this.context = context;
    this.workspaceFolder = workspaceFolder;
    this.telemetry = telemetry;
    this.ruby = new Ruby(context, workspaceFolder);
    this.createTestItems = createTestItems;

    this.registerRestarts(context);
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
        See [Troubleshooting](https://github.com/Shopify/vscode-ruby-lsp/blob/main/TROUBLESHOOTING.md) for help`,
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
    );

    try {
      STATUS_EMITTER.fire(this);
      await this.lspClient.start();
      this.lspClient.performAfterStart();
      STATUS_EMITTER.fire(this);
    } catch (error: any) {
      this.error = true;
      LOG_CHANNEL.error(`Error starting the server: ${error.message}`);
    }
  }

  async stop() {
    await this.lspClient?.stop();
  }

  async restart() {
    try {
      if (await this.rebaseInProgress()) {
        return;
      }

      if (this.lspClient) {
        await this.stop();
        await this.lspClient.dispose();
        await this.start();
      } else {
        await this.start();
      }
    } catch (error: any) {
      this.error = true;
      LOG_CHANNEL.error(`Error restarting the server: ${error.message}`);
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
        LOG_CHANNEL.error(`Failed to update global ruby-lsp gem: ${error}`);
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
      new vscode.RelativePattern(this.workspaceFolder.uri.fsPath, pattern),
    );
    context.subscriptions.push(watcher);

    watcher.onDidChange(this.restart.bind(this));
    watcher.onDidCreate(this.restart.bind(this));
    watcher.onDidDelete(this.restart.bind(this));
  }

  // If the `.git` folder exists and `.git/rebase-merge` or `.git/rebase-apply` exists, then we're in the middle of a
  // rebase
  private async rebaseInProgress() {
    const gitFolder = path.join(this.workspaceFolder.uri.fsPath, ".git");

    if (!(await pathExists(gitFolder))) {
      return false;
    }

    if (
      (await pathExists(path.join(gitFolder, "rebase-merge"))) ||
      (await pathExists(path.join(gitFolder, "rebase-apply")))
    ) {
      return true;
    }

    return false;
  }
}
