import { createHash } from "crypto";

import * as vscode from "vscode";
import { CodeLens, State } from "vscode-languageclient/node";

import { Ruby } from "./ruby";
import Client from "./client";
import { asyncExec, LOG_CHANNEL, WorkspaceInterface, STATUS_EMITTER, debounce } from "./common";
import { WorkspaceChannel } from "./workspaceChannel";

const WATCHED_FILES = ["Gemfile.lock", "gems.locked"];

interface GitExtension {
  exports: {
    getAPI: (version: number) => {
      openRepository: (uri: vscode.Uri) => Promise<{ rootUri: vscode.Uri } | undefined>;
    };
  };
}

export class Workspace implements WorkspaceInterface {
  public lspClient?: Client;
  public readonly ruby: Ruby;
  public readonly createTestItems: (response: CodeLens[]) => void;
  public readonly workspaceFolder: vscode.WorkspaceFolder;
  public readonly outputChannel: WorkspaceChannel;
  private readonly context: vscode.ExtensionContext;
  private readonly isMainWorkspace: boolean;
  private readonly telemetry: vscode.TelemetryLogger;
  private readonly virtualDocuments = new Map<string, string>();
  private readonly restartDocumentShas = new Map<string, string>();
  private needsRestart = false;

  // Holds all subscriptions that are related to this workspace and that should be disposed of if the workspace is
  // deactivated. Notice that we do not dispose of the workspace when restarting the LSP client, we only dispose of the
  // client itself
  private subscriptions: vscode.Disposable[] = [];
  #inhibitRestart = false;
  #error = false;

  private readonly debouncedRestart = debounce(async (reason: string) => {
    this.outputChannel.info(`Restarting the Ruby LSP because ${reason}`);
    await this.restart();
  }, 5000);

  constructor(
    context: vscode.ExtensionContext,
    workspaceFolder: vscode.WorkspaceFolder,
    telemetry: vscode.TelemetryLogger,
    createTestItems: (response: CodeLens[]) => void,
    virtualDocuments: Map<string, string>,
    isMainWorkspace = false,
  ) {
    this.context = context;
    this.workspaceFolder = workspaceFolder;
    this.outputChannel = new WorkspaceChannel(workspaceFolder.name, LOG_CHANNEL);
    this.telemetry = telemetry;
    this.ruby = new Ruby(context, workspaceFolder, this.outputChannel, telemetry);
    this.createTestItems = createTestItems;
    this.isMainWorkspace = isMainWorkspace;
    this.virtualDocuments = virtualDocuments;
  }

  // Activate this workspace. This method is intended to be invoked only once, unlikely `start` which may be invoked
  // multiple times due to restarts
  async activate() {
    const gitExtension: GitExtension | undefined = vscode.extensions.getExtension("vscode.git");
    let rootGitUri = this.workspaceFolder.uri;

    // If the git extension is available, use that to find the root of the git repository
    if (gitExtension) {
      const api = gitExtension.exports.getAPI(1);
      const repository = await api.openRepository(this.workspaceFolder.uri);

      if (repository) {
        rootGitUri = repository.rootUri;
      }
    }

    this.registerCreateDeleteWatcher(rootGitUri, ".git/{rebase-merge,rebase-apply,BISECT_START,CHERRY_PICK_HEAD}");

    this.registerRestarts();

    // Eagerly calculate SHAs for the watched files to avoid unnecessary restarts
    for (const file of WATCHED_FILES) {
      const uri = vscode.Uri.joinPath(this.workspaceFolder.uri, file);
      const currentSha = await this.fileContentsSha(uri);

      if (!currentSha) {
        continue;
      }

      this.restartDocumentShas.set(uri.fsPath, currentSha);
    }
  }

  async start(debugMode?: boolean) {
    await this.ruby.activateRuby();

    if (this.ruby.error) {
      this.error = true;
      return;
    }

    try {
      const stat = await vscode.workspace.fs.stat(this.workspaceFolder.uri);

      // If permissions is undefined, then we have all permissions. If it's set, the only possible value currently is
      // readonly, so it means VS Code does not have write permissions to the workspace URI and creating the custom
      // bundle would fail. We throw here just to catch it immediately below and show the error to the user
      if (stat.permissions) {
        throw new Error(`Directory ${this.workspaceFolder.uri.fsPath} is readonly.`);
      }
    } catch (_error: any) {
      this.error = true;

      await vscode.window.showErrorMessage(
        `Directory ${this.workspaceFolder.uri.fsPath} is not writable. The Ruby LSP server needs to be able to create a
        .ruby-lsp directory to function appropriately. Consider switching to a directory for which VS Code has write
        permissions`,
      );

      return;
    }

    try {
      await this.installOrUpdateServer(false);
    } catch (error: any) {
      this.error = true;
      await vscode.window.showErrorMessage(
        `Failed to setup the bundle: ${error.message}. \
        See [Troubleshooting](https://shopify.github.io/ruby-lsp/troubleshooting.html) for help`,
      );

      return;
    }

    // The `start` method can be invoked through commands - even if there's an LSP client already running. We need to
    // ensure that the existing client for this workspace has been stopped and disposed of before we create a new one
    if (this.lspClient) {
      await this.stop();
    }

    this.lspClient = new Client(
      this.context,
      this.telemetry,
      this.ruby,
      this.createTestItems,
      this.workspaceFolder,
      this.outputChannel,
      this.virtualDocuments,
      this.isMainWorkspace,
      debugMode,
    );

    try {
      STATUS_EMITTER.fire(this);
      await vscode.window.withProgress(
        {
          location: vscode.ProgressLocation.Window,
          title: "Initializing Ruby LSP",
        },
        async () => {
          await this.lspClient!.start();
          await this.lspClient!.afterStart();
        },
      );
      STATUS_EMITTER.fire(this);

      // If something triggered a restart while we were still booting, then now we need to perform the restart since the
      // server can now handle shutdown requests
      if (this.needsRestart) {
        this.needsRestart = false;
        await this.debouncedRestart("a restart was requested while the server was still booting");
      }
    } catch (error: any) {
      this.error = true;
      this.outputChannel.error(`Error starting the server: ${error.message}`);
    }
  }

  async stop() {
    await this.lspClient?.dispose();
  }

  async restart() {
    try {
      if (this.#inhibitRestart) {
        return;
      }

      this.error = false;

      // If there's no client, then we can just start a new one
      if (!this.lspClient) {
        return this.start();
      }

      let canRestart = false;

      switch (this.lspClient.state) {
        // If the server is still starting, then it may not be ready to handle a shutdown request yet. Trying to send
        // one could lead to a hanging process. Instead we set a flag and only restart once the server finished booting
        // in `start`
        case State.Starting:
          this.needsRestart = true;
          break;
        // If the server is running, we want to stop it, dispose of the client and start a new one
        case State.Running:
          // If the server doesn't support checking the validity of the composed bundle or if composing the bundle was
          // successful, then we can restart
          canRestart =
            !this.lspClient.initializeResult?.capabilities.experimental.compose_bundle ||
            (await this.composingBundleSucceeds());

          if (canRestart) {
            await this.stop();
            this.lspClient = undefined;
            await this.start();
          }
          break;
        // If the server is already stopped, then we need to dispose it and start a new one
        case State.Stopped:
          await this.stop();
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
    this.subscriptions.forEach((subscription) => subscription.dispose());
    await this.lspClient?.dispose();
  }

  // Install or update the `ruby-lsp` gem globally with `gem install ruby-lsp` or `gem update ruby-lsp`. We only try to
  // update on a daily basis, not every time the server boots
  async installOrUpdateServer(manualInvocation: boolean): Promise<void> {
    // If there's a user configured custom bundle to run the LSP, then we do not perform auto-updates and let the user
    // manage that custom bundle themselves
    const customBundle: string = vscode.workspace.getConfiguration("rubyLsp").get("bundleGemfile")!;

    if (customBundle.length > 0) {
      return;
    }

    const oneDayInMs = 24 * 60 * 60 * 1000;
    const lastUpdatedAt: number | undefined = this.context.workspaceState.get("rubyLsp.lastGemUpdate");

    // Theses are the Ruby LSP's own dependencies, listed in `ruby-lsp.gemspec`
    const dependencies = ["ruby-lsp", "language_server-protocol", "prism", "rbs"];

    const { stdout } = await asyncExec(`gem list ${dependencies.join(" ")}`, {
      cwd: this.workspaceFolder.uri.fsPath,
      env: this.ruby.env,
    });

    // If any of the Ruby LSP's dependencies are missing, we need to install them. For example, if the user runs `gem
    // uninstall prism`, then we must ensure it's installed or else rubygems will fail when trying to launch the
    // executable
    if (!dependencies.every((dep) => new RegExp(`${dep}\\s`).exec(stdout))) {
      await asyncExec("gem install ruby-lsp", {
        cwd: this.workspaceFolder.uri.fsPath,
        env: this.ruby.env,
      });

      await this.context.workspaceState.update("rubyLsp.lastGemUpdate", Date.now());
      return;
    }

    // In addition to updating the global installation of the ruby-lsp gem, if the user manually requested an update, we
    // should delete the `.ruby-lsp` to ensure that we'll lock a new version of the server that will actually be booted
    if (manualInvocation) {
      const composedBundleUri = vscode.Uri.joinPath(this.workspaceFolder.uri, ".ruby-lsp");

      try {
        await vscode.workspace.fs.delete(composedBundleUri, {
          recursive: true,
        });
      } catch (_error) {
        this.outputChannel.info(`Tried deleting ${composedBundleUri.fsPath}, but it doesn't exist`);
      }
    }

    // If we haven't updated the gem in the last 24 hours or if the user manually asked for an update, update it
    if (manualInvocation || lastUpdatedAt === undefined || Date.now() - lastUpdatedAt > oneDayInMs) {
      try {
        await asyncExec("gem update ruby-lsp", {
          cwd: this.workspaceFolder.uri.fsPath,
          env: this.ruby.env,
        });
        await this.context.workspaceState.update("rubyLsp.lastGemUpdate", Date.now());
      } catch (error: any) {
        // If we fail to update the global installation of `ruby-lsp`, we don't want to prevent the server from starting
        this.outputChannel.error(`Failed to update global ruby-lsp gem: ${error}`);
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

  get inhibitRestart() {
    return this.#inhibitRestart;
  }

  async execute(command: string, log = false) {
    if (log) {
      this.outputChannel.show();
      this.outputChannel.info(`Running "${command}"`);
    }

    const result = await asyncExec(command, {
      env: this.ruby.env,
      cwd: this.workspaceFolder.uri.fsPath,
    });

    if (log) {
      if (result.stderr.length > 0) {
        this.outputChannel.error(result.stderr);
      } else {
        this.outputChannel.info(result.stdout);
      }
    }

    return result;
  }

  private registerRestarts() {
    this.createRestartWatcher(`{${WATCHED_FILES.join(",")}}`);

    // If a configuration that affects the Ruby LSP has changed, update the client options using the latest
    // configuration and restart the server
    this.subscriptions.push(
      vscode.workspace.onDidChangeConfiguration(async (event) => {
        if (event.affectsConfiguration("rubyLsp")) {
          await this.debouncedRestart("configuration changed");
        }
      }),
    );
  }

  private createRestartWatcher(pattern: string) {
    const watcher = vscode.workspace.createFileSystemWatcher(new vscode.RelativePattern(this.workspaceFolder, pattern));

    // Handler for only triggering restart if the contents of the file have been modified. If the file was just touched,
    // but the contents are the same, we don't want to restart
    const debouncedRestartWithHashCheck = async (uri: vscode.Uri) => {
      const fsPath = uri.fsPath;
      const currentSha = await this.fileContentsSha(uri);

      if (currentSha && this.restartDocumentShas.get(fsPath) !== currentSha) {
        this.restartDocumentShas.set(fsPath, currentSha);
        await this.debouncedRestart(`${fsPath} changed, matching ${pattern}`);
      }
    };

    const debouncedRestart = async (uri: vscode.Uri) => {
      this.restartDocumentShas.delete(uri.fsPath);
      await this.debouncedRestart(`${uri.fsPath} changed, matching ${pattern}`);
    };

    this.subscriptions.push(
      watcher,
      watcher.onDidChange(debouncedRestartWithHashCheck),
      // Interestingly, we are seeing create events being fired even when the file already exists. If a create event is
      // fired for an update to an existing file, then we need to check if the contents still match to prevent unwanted
      // restarts
      watcher.onDidCreate(debouncedRestartWithHashCheck),
      watcher.onDidDelete(debouncedRestart),
    );
  }

  private registerCreateDeleteWatcher(base: vscode.Uri, glob: string) {
    const workspaceWatcher = vscode.workspace.createFileSystemWatcher(new vscode.RelativePattern(base, glob));

    const start = () => {
      this.#inhibitRestart = true;
    };

    const stop = async (uri: vscode.Uri) => {
      this.#inhibitRestart = false;
      await this.debouncedRestart(`${uri.fsPath} changed, matching ${glob}`);
    };

    this.subscriptions.push(
      workspaceWatcher,
      // When one of the 'inhibit restart' files are created, we set this flag to prevent restarting during that action
      workspaceWatcher.onDidCreate(start),
      // Once they are deleted and the action is complete, then we restart
      workspaceWatcher.onDidDelete(stop),
    );
  }

  private async fileContentsSha(uri: vscode.Uri): Promise<string | undefined> {
    let fileContents;

    try {
      fileContents = await vscode.workspace.fs.readFile(uri);
    } catch (_error: any) {
      return undefined;
    }

    const hash = createHash("sha256");
    hash.update(fileContents.toString());
    return hash.digest("hex");
  }

  private async composingBundleSucceeds(): Promise<boolean> {
    if (!this.lspClient) {
      return false;
    }

    try {
      const response: { success: boolean } = await this.lspClient.sendRequest("rubyLsp/composeBundle");
      return response.success;
    } catch (_error: any) {
      return false;
    }
  }
}
