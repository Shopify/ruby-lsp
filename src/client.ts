import path from "path";
import fs from "fs";
import readline from "readline";
import { promisify } from "util";
import { exec, spawn } from "child_process";

import * as vscode from "vscode";
import {
  LanguageClientOptions,
  LanguageClient,
  Executable,
  RevealOutputChannelOn,
} from "vscode-languageclient/node";

import { Telemetry } from "./telemetry";
import { Ruby } from "./ruby";
import { StatusItems, Command, ServerState, ClientInterface } from "./status";

const LSP_NAME = "Ruby LSP";
const asyncExec = promisify(exec);
const ONE_DAY_IN_MS = 24 * 60 * 60 * 1000;

interface EnabledFeatures {
  [key: string]: boolean;
}

export default class Client implements ClientInterface {
  private client: LanguageClient | undefined;
  private workingFolder: string;
  private telemetry: Telemetry;
  private statusItems: StatusItems;
  private outputChannel = vscode.window.createOutputChannel(LSP_NAME);
  private bundleInstallCancellationSource:
    | vscode.CancellationTokenSource
    | undefined;

  #context: vscode.ExtensionContext;
  #ruby: Ruby;
  #state: ServerState = ServerState.Starting;

  constructor(
    context: vscode.ExtensionContext,
    telemetry: Telemetry,
    ruby: Ruby
  ) {
    this.workingFolder = vscode.workspace.workspaceFolders![0].uri.fsPath;
    this.telemetry = telemetry;
    this.#context = context;
    this.#ruby = ruby;
    this.statusItems = new StatusItems(this);
    this.registerCommands();
    this.registerAutoRestarts();
  }

  async start() {
    if (this.ruby.error) {
      this.state = ServerState.Error;
      return;
    }

    this.state = ServerState.Starting;

    try {
      await this.setupCustomGemfile();
    } catch (error: any) {
      this.state = ServerState.Error;

      // The progress dialog can't be closed by the user, so we have to guarantee that we catch errors
      vscode.window.showErrorMessage(
        `Failed to setup the bundle: ${error.message}. \
            See [Troubleshooting](https://github.com/Shopify/vscode-ruby-lsp#troubleshooting) for instructions`
      );

      return;
    }

    const executableOptions = {
      cwd: this.workingFolder,
      env: this.ruby.env,
    };

    const executable: Executable = {
      command: "bundle",
      args: ["exec", "ruby-lsp"],
      options: executableOptions,
    };

    const debugExecutable: Executable = {
      command: "bundle",
      args: ["exec", "ruby-lsp", "--debug"],
      options: executableOptions,
    };

    const configuration = vscode.workspace.getConfiguration("rubyLsp");
    const clientOptions: LanguageClientOptions = {
      documentSelector: [{ scheme: "file", language: "ruby" }],
      diagnosticCollectionName: LSP_NAME,
      outputChannel: this.outputChannel,
      revealOutputChannelOn: RevealOutputChannelOn.Never,
      initializationOptions: {
        enabledFeatures: this.listOfEnabledFeatures(),
        experimentalFeaturesEnabled: configuration.get(
          "enableExperimentalFeatures"
        ),
        formatter: configuration.get("formatter"),
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

    this.client = new LanguageClient(
      LSP_NAME,
      { run: executable, debug: debugExecutable },
      clientOptions
    );

    this.client.onTelemetry((event) =>
      this.telemetry.sendEvent({
        ...event,
        rubyVersion: this.ruby.rubyVersion,
        yjitEnabled: this.ruby.yjitEnabled,
      })
    );

    await this.client.start();

    this.state = ServerState.Running;
  }

  async stop(): Promise<void> {
    if (this.client) {
      this.state = ServerState.Stopped;

      return this.client.stop();
    }
  }

  async restart() {
    try {
      if (this.client?.isRunning()) {
        await this.stop();
        await this.start();
      } else {
        await this.start();
      }
    } catch (error: any) {
      this.state = ServerState.Error;

      this.outputChannel.appendLine(
        `Error restarting the server: ${error.message}`
      );
    }
  }

  get ruby(): Ruby {
    return this.#ruby;
  }

  private set ruby(ruby: Ruby) {
    this.#ruby = ruby;
  }

  get context(): vscode.ExtensionContext {
    return this.#context;
  }

  private set context(context: vscode.ExtensionContext) {
    this.#context = context;
  }

  get state(): ServerState {
    return this.#state;
  }

  private set state(state: ServerState) {
    this.#state = state;
    this.statusItems.refresh();
  }

  private registerCommands() {
    this.context.subscriptions.push(
      vscode.commands.registerCommand(Command.Start, this.start.bind(this)),
      vscode.commands.registerCommand(Command.Restart, this.restart.bind(this)),
      vscode.commands.registerCommand(Command.Stop, this.stop.bind(this)),
      vscode.commands.registerCommand(
        Command.Update,
        this.updateServer.bind(this)
      )
    );
  }

  private async setupCustomGemfile() {
    // If we're working on the ruby-lsp itself, we can't create a custom Gemfile or we'd be trying to activate the same
    // gem twice
    if (path.basename(this.workingFolder) === "ruby-lsp") {
      await this.bundleInstall();
      return;
    }

    // Create the .ruby-lsp directory if it doesn't exist
    const rubyLspDirectory = path.join(this.workingFolder, ".ruby-lsp");

    if (!fs.existsSync(rubyLspDirectory)) {
      fs.mkdirSync(rubyLspDirectory);
    }

    // Ignore the .ruby-lsp directory automatically
    fs.writeFileSync(path.join(rubyLspDirectory, ".gitignore"), "*");

    // Generate the custom Gemfile that includes the `ruby-lsp`
    const customGemfilePath = path.join(rubyLspDirectory, "Gemfile");
    const gemfile = [
      "# This custom gemfile is automatically generated by the Ruby LSP extension.",
      "# It should be automatically git ignored, but in any case: do not commit it to your repository.",
      "",
    ];

    const gemEntry =
      'gem "ruby-lsp", require: false, group: :development, source: "https://rubygems.org"';

    // Only try to evaluate the top level Gemfile if there is one. Otherwise, we'll just create our own Gemfile
    if (fs.existsSync(path.join(this.workingFolder, "Gemfile"))) {
      // For eval_gemfile, the paths must be absolute or else using the `path:` option for `gem` will fail
      gemfile.push('eval_gemfile(File.expand_path("../Gemfile", __dir__))');

      // If the `ruby-lsp` exists in the bundle, add it to the custom Gemfile commented out
      if (await this.rubyLspIsInBundle()) {
        // If it is already in the bundle, add the gem commented out to avoid conflicts
        gemfile.push(`# ${gemEntry}`);
      } else {
        // If it's not a part of the bundle, add it to the custom Gemfile
        gemfile.push(gemEntry);
      }
    } else {
      // If no Gemfile exists, add the `ruby-lsp` gem to the custom Gemfile
      gemfile.push(gemEntry);
    }

    // Add an empty line at the end of the file
    gemfile.push("");

    fs.writeFileSync(customGemfilePath, gemfile.join("\n"));

    const lastUpdatedAt: number | undefined = this.context.workspaceState.get(
      "rubyLsp.lastBundleInstall"
    );
    const gemfileLockPath = path.join(this.workingFolder, "Gemfile.lock");
    const customGemfileLockPath = path.join(
      this.workingFolder,
      ".ruby-lsp",
      "Gemfile.lock"
    );

    // Copy the Gemfile.lock and install gems to get `ruby-lsp` updates if
    // - it's been more than a day since the last time we checked for updates
    // - the Gemfile.lock has changed and we haven't yet updated .ruby-lsp/Gemfile.lock
    // - the gems aren't installed
    if (
      lastUpdatedAt === undefined ||
      Date.now() - lastUpdatedAt > ONE_DAY_IN_MS ||
      this.gemfilesAreOutOfSync(gemfileLockPath, customGemfileLockPath) ||
      !(await this.gemsAreInstalled(customGemfilePath))
    ) {
      await this.updateServer();
    }
  }

  private registerAutoRestarts() {
    this.createRestartWatcher("Gemfile.lock");
    this.createRestartWatcher("**/.rubocop.yml");

    // If a configuration that affects the Ruby LSP has changed, update the client options using the latest
    // configuration and restart the server
    vscode.workspace.onDidChangeConfiguration(async (event) => {
      if (event.affectsConfiguration("rubyLsp")) {
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

    return Object.keys(features).filter((key) => features[key]);
  }

  private async rubyLspIsInBundle(): Promise<boolean> {
    // When working on the Ruby LSP itself, it's always included in the bundle
    if (path.basename(this.workingFolder) === "ruby-lsp") {
      return true;
    }

    try {
      // If bundle show succeeds, it means the ruby-lsp gem is a part of the bundle
      await asyncExec(
        `BUNDLE_GEMFILE=${path.join(
          this.workingFolder,
          "Gemfile"
        )} bundle show ruby-lsp`,
        {
          cwd: this.workingFolder,
          env: this.ruby.env,
        }
      );
      return true;
    } catch (error) {
      return false;
    }
  }

  private async gemsAreInstalled(customGemfilePath: string): Promise<boolean> {
    try {
      await asyncExec(`BUNDLE_GEMFILE=${customGemfilePath} bundle check`, {
        cwd: this.workingFolder,
        env: this.ruby.env,
      });
      return true;
    } catch {
      return false;
    }
  }

  private gemfilesAreOutOfSync(
    gemfileLockPath: string,
    customGemfileLockPath: string
  ): boolean {
    // If there's no top level Gemfile.lock, there's nothing to sync
    if (!fs.existsSync(gemfileLockPath)) {
      return false;
    }

    // If there's no custom Gemfile.lock, then it hasn't been created yet and we must sync
    if (!fs.existsSync(customGemfileLockPath)) {
      return true;
    }

    // If the last modified time of the top level Gemfile.lock is greater than the custom Gemfile.lock, then changes
    // were made and we have to sync
    const lastModifiedAt = fs.statSync(gemfileLockPath).mtimeMs;
    const customLastModifiedAt = fs.statSync(customGemfileLockPath).mtimeMs;
    return lastModifiedAt > customLastModifiedAt;
  }

  private async updateServer(): Promise<void> {
    const gemfileLockPath = path.join(this.workingFolder, "Gemfile.lock");
    const customGemfileLockPath = path.join(
      this.workingFolder,
      ".ruby-lsp",
      "Gemfile.lock"
    );

    // Copy the current `Gemfile.lock` to the `.ruby-lsp` directory to make sure we're using the right versions of
    // RuboCop and related extensions. Because we do this in every initialization, we always use the latest version of
    // the Ruby LSP
    if (fs.existsSync(gemfileLockPath)) {
      fs.cpSync(gemfileLockPath, customGemfileLockPath);
    }

    const customGemfilePath = path.join(
      this.workingFolder,
      ".ruby-lsp",
      "Gemfile"
    );

    await vscode.window.withProgress(
      {
        location: vscode.ProgressLocation.Notification,
        title: "Setting up the bundle",
        cancellable: true,
      },
      (progress, token) => {
        if (this.bundleInstallCancellationSource) {
          this.bundleInstallCancellationSource.cancel();
          this.bundleInstallCancellationSource.dispose();
        }

        this.bundleInstallCancellationSource =
          new vscode.CancellationTokenSource();

        token.onCancellationRequested(() => {
          this.bundleInstallCancellationSource!.cancel();
          this.bundleInstallCancellationSource!.dispose();
        });

        return this.bundleInstall(customGemfilePath, {
          progress,
          token: this.bundleInstallCancellationSource.token,
        });
      }
    );

    // Update the last time we checked for updates
    this.context.workspaceState.update("rubyLsp.lastBundleInstall", Date.now());
  }

  private async bundleInstall(
    bundleGemfile?: string,
    options?: {
      progress?: vscode.Progress<{ message?: string }>;
      token?: vscode.CancellationToken;
    }
  ) {
    const env = { ...this.ruby.env, BUNDLE_GEMFILE: bundleGemfile };

    return new Promise<void>((resolve, reject) => {
      const abortController = new AbortController();

      if (options?.token) {
        options.token.onCancellationRequested(() => {
          abortController.abort();
        });
      }

      this.outputChannel.appendLine(">> Running `bundle install`...");

      const install = spawn("bundle", ["install"], {
        cwd: this.workingFolder,
        signal: abortController.signal,
        env,
      });

      const stdout = readline
        .createInterface({
          input: install.stdout,
          terminal: false,
        })
        .on("line", (line) => {
          this.outputChannel.appendLine(`BUNDLER> ${line}`);

          if (options?.progress) {
            options.progress.report({ message: line });
          }
        });

      const stderr = readline
        .createInterface({
          input: install.stderr,
          terminal: false,
        })
        .on("line", (line) => {
          this.outputChannel.appendLine(`ERROR> ${line}`);
        });

      install.on("close", (code) => {
        stdout.close();
        stderr.close();

        this.outputChannel.appendLine(
          `>> \`bundle install\` exited with code ${code}`
        );

        if (code === 0) {
          resolve();
        } else {
          reject(new Error(`bundle install exited with code ${code}`));
        }
      });

      install.on("error", (error) => {
        stdout.close();
        stderr.close();
        reject(error);
      });
    });
  }
}
