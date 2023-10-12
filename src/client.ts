import path from "path";
import fs from "fs";
import { promisify } from "util";
import { exec } from "child_process";
import { performance as Perf } from "perf_hooks";

import * as vscode from "vscode";
import {
  LanguageClientOptions,
  LanguageClient,
  Executable,
  RevealOutputChannelOn,
  CodeLens,
  Range,
  ExecutableOptions,
  ServerOptions,
  DiagnosticPullOptions,
  MessageSignature,
} from "vscode-languageclient/node";

import { Telemetry, RequestEvent } from "./telemetry";
import { Ruby } from "./ruby";
import { StatusItems, Command, ServerState, ClientInterface } from "./status";
import { TestController } from "./testController";

const LSP_NAME = "Ruby LSP";
const asyncExec = promisify(exec);

interface EnabledFeatures {
  [key: string]: boolean;
}

type SyntaxTreeResponse = { ast: string } | null;

export default class Client implements ClientInterface {
  private client: LanguageClient | undefined;
  private readonly workingFolder: string;
  private readonly telemetry: Telemetry;
  private readonly statusItems: StatusItems;
  private readonly outputChannel = vscode.window.createOutputChannel(LSP_NAME);
  private readonly testController: TestController;
  private readonly customBundleGemfile: string = vscode.workspace
    .getConfiguration("rubyLsp")
    .get("bundleGemfile")!;

  private readonly baseFolder;
  private requestId = 0;

  #context: vscode.ExtensionContext;
  #ruby: Ruby;
  #state: ServerState = ServerState.Starting;
  #formatter: string;

  constructor(
    context: vscode.ExtensionContext,
    telemetry: Telemetry,
    ruby: Ruby,
    testController: TestController,
    workingFolder = vscode.workspace.workspaceFolders![0].uri.fsPath,
  ) {
    this.workingFolder = workingFolder;
    this.baseFolder = path.basename(this.workingFolder);
    this.telemetry = telemetry;
    this.testController = testController;
    this.#context = context;
    this.#ruby = ruby;
    this.#formatter = "";
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
      await this.installOrUpdateServer();
    } catch (error: any) {
      this.state = ServerState.Error;

      // The progress dialog can't be closed by the user, so we have to guarantee that we catch errors
      vscode.window.showErrorMessage(
        `Failed to setup the bundle: ${error.message}. \
            See [Troubleshooting](https://github.com/Shopify/vscode-ruby-lsp#troubleshooting) for instructions`,
      );

      return;
    }

    const configuration = vscode.workspace.getConfiguration("rubyLsp");
    const clientOptions: LanguageClientOptions = {
      documentSelector: [{ language: "ruby" }],
      diagnosticCollectionName: LSP_NAME,
      outputChannel: this.outputChannel,
      revealOutputChannelOn: RevealOutputChannelOn.Never,
      diagnosticPullOptions: this.diagnosticPullOptions(),
      initializationOptions: {
        enabledFeatures: this.listOfEnabledFeatures(),
        experimentalFeaturesEnabled: configuration.get(
          "enableExperimentalFeatures",
        ),
        formatter: configuration.get("formatter"),
      },
      middleware: {
        provideCodeLenses: async (document, token, next) => {
          if (!this.client) {
            return null;
          }

          const response = await next(document, token);

          if (response) {
            const testLenses = response.filter(
              (codeLens) => (codeLens as CodeLens).data.type === "test",
            ) as CodeLens[];

            if (testLenses.length) {
              this.testController.createTestItems(testLenses);
            }
          }

          return response;
        },
        provideOnTypeFormattingEdits: async (
          document,
          position,
          ch,
          options,
          token,
          _next,
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
                token,
              );

            if (!response) {
              return null;
            }

            // Find the $0 anchor to move the cursor
            const cursorPosition = response.find(
              (edit) => edit.newText === "$0",
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
                cursorPosition.range.end,
              ),
            );

            return null;
          }

          return undefined;
        },
        sendRequest: async <TP, T>(
          type: string | MessageSignature,
          param: TP | undefined,
          token: vscode.CancellationToken,
          next: (
            type: string | MessageSignature,
            param?: TP,
            token?: vscode.CancellationToken,
          ) => Promise<T>,
        ) => {
          return this.benchmarkMiddleware(type, param, () =>
            next(type, param, token),
          );
        },
        sendNotification: async <TR>(
          type: string | MessageSignature,
          next: (type: string | MessageSignature, params?: TR) => Promise<void>,
          params: TR,
        ) => {
          return this.benchmarkMiddleware(type, params, () =>
            next(type, params),
          );
        },
      },
    };

    this.client = new LanguageClient(
      LSP_NAME,
      this.executables(),
      clientOptions,
    );

    try {
      await this.client.start();
    } catch (error: any) {
      this.state = ServerState.Error;
      this.outputChannel.appendLine(
        `Error restarting the server: ${error.message}`,
      );
      return;
    }

    // We cannot inquire anything related to the bundle before the custom bundle logic in the server runs
    await this.determineFormatter();
    this.telemetry.serverVersion = await this.getServerVersion();

    this.state = ServerState.Running;
  }

  async stop(): Promise<void> {
    if (this.client) {
      await this.client.stop();
      this.state = ServerState.Stopped;
    }
  }

  async restart() {
    // If the server is already starting/restarting we should try to do it again. One scenario where that may happen is
    // when doing git pull, which may trigger a restart for two watchers: .rubocop.yml and Gemfile.lock. In those cases,
    // we only want to restart once and not twice to avoid leading to a duplicate process
    if (this.state === ServerState.Starting) {
      return;
    }

    if (this.rebaseInProgress()) {
      return;
    }

    try {
      this.state = ServerState.Starting;

      if (this.client?.isRunning()) {
        await this.stop();
        await this.start();
      } else {
        await this.start();
      }
    } catch (error: any) {
      this.state = ServerState.Error;

      this.outputChannel.appendLine(
        `Error restarting the server: ${error.message}`,
      );
    }
  }

  dispose() {
    this.client?.dispose();
    this.outputChannel.dispose();
  }

  get ruby(): Ruby {
    return this.#ruby;
  }

  private set ruby(ruby: Ruby) {
    this.#ruby = ruby;
  }

  get formatter(): string {
    return this.#formatter;
  }

  get serverVersion(): string | undefined {
    return this.telemetry.serverVersion;
  }

  async determineFormatter() {
    const configuration = vscode.workspace.getConfiguration("rubyLsp");
    const configuredFormatter: string = configuration.get("formatter")!;

    if (configuredFormatter === "auto") {
      if (await this.projectHasDependency(/^rubocop/)) {
        this.#formatter = "rubocop";
      } else if (await this.projectHasDependency(/^syntax_tree$/)) {
        this.#formatter = "syntax_tree";
      } else {
        this.#formatter = "none";
      }
    } else {
      this.#formatter = configuredFormatter;
    }
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
        this.installOrUpdateServer.bind(this),
      ),
      vscode.commands.registerCommand(
        Command.OpenLink,
        this.openLink.bind(this),
      ),
      vscode.commands.registerCommand(
        Command.ShowSyntaxTree,
        this.showSyntaxTree.bind(this),
      ),
    );
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
      new vscode.RelativePattern(this.workingFolder, pattern),
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

  private async projectHasDependency(gemName: RegExp): Promise<boolean> {
    try {
      // We can't include `BUNDLE_GEMFILE` here, because we want to check if the project's bundle includes the
      // dependency and not our custom bundle
      const { BUNDLE_GEMFILE, ...withoutBundleGemfileEnv } = this.ruby.env;

      // exit with an error if gemName not a dependency or is a transitive dependency.
      // exit with success if gemName is a direct dependency.
      await asyncExec(
        `ruby -rbundler -e "exit 1 unless Bundler.locked_gems.dependencies.keys.grep(${gemName}).any?"`,
        {
          cwd: this.workingFolder,
          env: withoutBundleGemfileEnv,
        },
      );
      return true;
    } catch (error) {
      return false;
    }
  }

  private async installOrUpdateServer(): Promise<void> {
    // If there's a user configured custom bundle to run the LSP, then we do not perform auto-updates and let the user
    // manage that custom bundle themselves
    if (this.hasUserDefinedCustomBundle()) {
      return;
    }

    const oneDayInMs = 24 * 60 * 60 * 1000;
    const lastUpdatedAt: number | undefined = this.context.workspaceState.get(
      "rubyLsp.lastGemUpdate",
    );

    const { stdout } = await asyncExec("gem list ruby-lsp", {
      cwd: this.workingFolder,
      env: this.ruby.env,
    });

    // If the gem is not yet installed, install it
    if (!stdout.includes("ruby-lsp")) {
      await asyncExec("gem install ruby-lsp", {
        cwd: this.workingFolder,
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
          cwd: this.workingFolder,
          env: this.ruby.env,
        });
        this.context.workspaceState.update("rubyLsp.lastGemUpdate", Date.now());
      } catch (error) {
        // If we fail to update the global installation of `ruby-lsp`, we don't want to prevent the server from starting
        this.outputChannel.appendLine(
          `Failed to update global ruby-lsp gem: ${error}`,
        );
      }
    }
  }

  private async getServerVersion(): Promise<string> {
    let bundleGemfile;

    // If a custom Gemfile was configured outside of the project, use that. Otherwise, prefer our custom bundle over the
    // app's bundle
    if (this.hasUserDefinedCustomBundle()) {
      bundleGemfile = path.isAbsolute(this.customBundleGemfile)
        ? this.customBundleGemfile
        : path.resolve(path.join(this.workingFolder, this.customBundleGemfile));
    } else if (
      fs.existsSync(path.join(this.workingFolder, ".ruby-lsp", "Gemfile"))
    ) {
      bundleGemfile = path.join(this.workingFolder, ".ruby-lsp", "Gemfile");
    } else {
      bundleGemfile = path.join(this.workingFolder, "Gemfile");
    }

    const result = await asyncExec(
      `bundle exec ruby -e "require 'ruby-lsp'; print RubyLsp::VERSION"`,
      {
        cwd: this.workingFolder,
        env: { ...this.ruby.env, BUNDLE_GEMFILE: bundleGemfile },
      },
    );

    return result.stdout;
  }

  // If the `.git` folder exists and `.git/rebase-merge` or `.git/rebase-apply` exists, then we're in the middle of a
  // rebase
  private rebaseInProgress() {
    const gitFolder = path.join(this.workingFolder, ".git");

    return (
      fs.existsSync(gitFolder) &&
      (fs.existsSync(path.join(gitFolder, "rebase-merge")) ||
        fs.existsSync(path.join(gitFolder, "rebase-apply")))
    );
  }

  private async openLink(link: string) {
    await this.telemetry.sendCodeLensEvent("link");
    vscode.env.openExternal(vscode.Uri.parse(link));
  }

  private async showSyntaxTree() {
    const activeEditor = vscode.window.activeTextEditor;

    if (this.client && activeEditor) {
      const document = activeEditor.document;

      if (document.languageId !== "ruby") {
        vscode.window.showErrorMessage("Show syntax tree: not a Ruby file");
        return;
      }

      const selection = activeEditor.selection;
      let range: Range | undefined;

      // Anchor is the first point and active is the last point in the selection. If both are the same, nothing is
      // selected
      if (!selection.active.isEqual(selection.anchor)) {
        // If you start selecting from below and go up, then the selection is reverted
        if (selection.isReversed) {
          range = Range.create(
            selection.active.line,
            selection.active.character,
            selection.anchor.line,
            selection.anchor.character,
          );
        } else {
          range = Range.create(
            selection.anchor.line,
            selection.anchor.character,
            selection.active.line,
            selection.active.character,
          );
        }
      }

      const response: SyntaxTreeResponse = await this.client.sendRequest(
        "rubyLsp/textDocument/showSyntaxTree",
        {
          textDocument: { uri: activeEditor.document.uri.toString() },
          range,
        },
      );

      if (response) {
        const document = await vscode.workspace.openTextDocument(
          vscode.Uri.from({
            scheme: "ruby-lsp",
            path: "show-syntax-tree",
            query: response.ast,
          }),
        );

        await vscode.window.showTextDocument(document, {
          viewColumn: vscode.ViewColumn.Beside,
          preserveFocus: true,
        });
      }
    }
  }

  private executables(): ServerOptions {
    let run: Executable;
    let debug: Executable;
    const branch: string = vscode.workspace
      .getConfiguration("rubyLsp")
      .get("branch")!;

    const executableOptions: ExecutableOptions = {
      cwd: this.workingFolder,
      env: this.ruby.env,
      shell: true,
    };

    // If there's a user defined custom bundle, we run the LSP with `bundle exec` and just trust the user configured
    // their bundle. Otherwise, we run the global install of the LSP and use our custom bundle logic in the server
    if (this.hasUserDefinedCustomBundle()) {
      run = {
        command: "bundle",
        args: ["exec", "ruby-lsp"],
        options: executableOptions,
      };

      debug = {
        command: "bundle",
        args: ["exec", "ruby-lsp", "--debug"],
        options: executableOptions,
      };
    } else {
      run = {
        command: "ruby-lsp",
        args: branch.length > 0 ? ["--branch", branch] : [],
        options: executableOptions,
      };

      debug = {
        command: "ruby-lsp",
        args: ["--debug"],
        options: executableOptions,
      };
    }

    return { run, debug };
  }

  private hasUserDefinedCustomBundle(): boolean {
    return this.customBundleGemfile.length > 0;
  }

  private diagnosticPullOptions(): DiagnosticPullOptions {
    const configuration = vscode.workspace.getConfiguration("rubyLsp");
    const pullOn: "change" | "save" | "both" =
      configuration.get("pullDiagnosticsOn")!;

    return {
      onChange: pullOn === "change" || pullOn === "both",
      onSave: pullOn === "save" || pullOn === "both",
    };
  }

  private async benchmarkMiddleware<T>(
    type: string | MessageSignature,
    params: any,
    runRequest: () => Promise<T>,
  ): Promise<T> {
    // Because of the custom bundle logic in the server, we can only fetch the server version after launching it. That
    // means some requests may be received before the computed the version. For those, we cannot send telemetry
    if (this.serverVersion === undefined) {
      return runRequest();
    }

    const telemetryData: RequestEvent = {
      request: typeof type === "string" ? type : type.method,
      rubyVersion: this.ruby.rubyVersion!,
      yjitEnabled: this.ruby.yjitEnabled!,
      lspVersion: this.serverVersion,
      requestTime: 0,
    };

    // If there are parameters in the request, include those
    if (params) {
      const castParam = { ...params } as { textDocument?: { uri: string } };

      if ("textDocument" in castParam) {
        const uri = castParam.textDocument?.uri.replace(
          // eslint-disable-next-line no-process-env
          process.env.HOME!,
          "~",
        );

        delete castParam.textDocument;
        telemetryData.uri = uri;
      }

      telemetryData.params = JSON.stringify(castParam);
    }

    let result: T | undefined;
    let errorResult;
    const benchmarkId = this.requestId++;

    // Execute the request measuring the time it takes to receive the response
    Perf.mark(`${benchmarkId}.start`);
    try {
      result = await runRequest();
    } catch (error: any) {
      // If any errors occurred in the request, we'll receive these from the LSP server
      telemetryData.errorClass = error.data.errorClass;
      telemetryData.errorMessage = error.data.errorMessage;
      telemetryData.backtrace = error.data.backtrace;
      errorResult = error;
    }
    Perf.mark(`${benchmarkId}.end`);

    // Insert benchmarked response time into telemetry data
    const bench = Perf.measure(
      "benchmarks",
      `${benchmarkId}.start`,
      `${benchmarkId}.end`,
    );
    telemetryData.requestTime = bench.duration;
    this.telemetry.sendEvent(telemetryData);

    // If there has been an error, we must throw it again. Otherwise we can return the result
    if (errorResult) {
      if (
        this.baseFolder === "ruby-lsp" ||
        this.baseFolder === "ruby-lsp-rails"
      ) {
        vscode.window.showErrorMessage(
          `Ruby LSP error ${errorResult.data.errorClass}: ${errorResult.data.errorMessage}\n\n
                ${errorResult.data.backtrace}`,
        );
      }

      throw errorResult;
    }

    return result!;
  }
}
