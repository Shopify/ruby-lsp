import path from "path";
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
  MessageSignature,
  DocumentSelector,
} from "vscode-languageclient/node";

import { LSP_NAME, ClientInterface, Addon } from "./common";
import { Telemetry, RequestEvent } from "./telemetry";
import { Ruby } from "./ruby";
import { WorkspaceChannel } from "./workspaceChannel";

type EnabledFeatures = Record<string, boolean>;

// Get the executables to start the server based on the user's configuration
function getLspExecutables(
  workspaceFolder: vscode.WorkspaceFolder,
  env: NodeJS.ProcessEnv,
): ServerOptions {
  let run: Executable;
  let debug: Executable;
  const config = vscode.workspace.getConfiguration("rubyLsp");
  const branch: string = config.get("branch")!;
  const customBundleGemfile: string = config.get("bundleGemfile")!;
  const useBundlerCompose: boolean = config.get("useBundlerCompose")!;
  const bypassTypechecker: boolean = config.get("bypassTypechecker")!;

  const executableOptions: ExecutableOptions = {
    cwd: workspaceFolder.uri.fsPath,
    env: bypassTypechecker
      ? { ...env, RUBY_LSP_BYPASS_TYPECHECKER: "true" }
      : env,
    shell: true,
  };

  // If there's a user defined custom bundle, we run the LSP with `bundle exec` and just trust the user configured
  // their bundle. Otherwise, we run the global install of the LSP and use our custom bundle logic in the server
  if (customBundleGemfile.length > 0) {
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
  } else if (useBundlerCompose) {
    run = {
      command: "bundle",
      args: ["compose", "gem", "ruby-lsp"],
      options: executableOptions,
    };

    debug = {
      command: "bundle",
      args: ["compose", "gem", "ruby-lsp", "--", "--debug"],
      options: executableOptions,
    };
  } else {
    const argsWithBranch = branch.length > 0 ? ["--branch", branch] : [];

    run = {
      command: "ruby-lsp",
      args: argsWithBranch,
      options: executableOptions,
    };

    debug = {
      command: "ruby-lsp",
      args: argsWithBranch.concat(["--debug"]),
      options: executableOptions,
    };
  }

  return { run, debug };
}

function collectClientOptions(
  configuration: vscode.WorkspaceConfiguration,
  workspaceFolder: vscode.WorkspaceFolder,
  outputChannel: WorkspaceChannel,
  ruby: Ruby,
  isMainWorkspace: boolean,
): LanguageClientOptions {
  const pullOn: "change" | "save" | "both" =
    configuration.get("pullDiagnosticsOn")!;

  const diagnosticPullOptions = {
    onChange: pullOn === "change" || pullOn === "both",
    onSave: pullOn === "save" || pullOn === "both",
  };

  const features: EnabledFeatures = configuration.get("enabledFeatures")!;
  const enabledFeatures = Object.keys(features).filter((key) => features[key]);

  const fsPath = workspaceFolder.uri.fsPath.replace(/\/$/, "");
  const documentSelector: DocumentSelector = [
    {
      language: "ruby",
      pattern: `${fsPath}/**/*`,
    },
  ];

  // Only the first language server we spawn should handle unsaved files, otherwise requests will be duplicated across
  // all workspaces
  if (isMainWorkspace) {
    documentSelector.push({
      language: "ruby",
      scheme: "untitled",
    });
  }

  // For each workspace, the language client is responsible for handling requests for:
  // 1. Files inside of the workspace itself
  // 2. Bundled gems
  // 3. Default gems

  if (ruby.env.GEM_PATH) {
    const parts = ruby.env.GEM_PATH.split(path.delimiter);

    // Because of how default gems are installed, the entry in the `GEM_PATH` is actually not exactly where the files
    // are located. With the regex, we are correcting the default gem path from this (where the files are not located)
    // /opt/rubies/3.3.1/lib/ruby/gems/3.3.0
    //
    // to this (where the files are actually stored)
    // /opt/rubies/3.3.1/lib/ruby/3.3.0
    parts.forEach((gemPath) => {
      documentSelector.push({
        language: "ruby",
        pattern: `${gemPath.replace(/lib\/ruby\/gems\/(?=\d)/, "lib/ruby/")}/**/*`,
      });
    });
  }

  return {
    documentSelector,
    workspaceFolder,
    diagnosticCollectionName: LSP_NAME,
    outputChannel,
    revealOutputChannelOn: RevealOutputChannelOn.Never,
    diagnosticPullOptions,
    initializationOptions: {
      enabledFeatures,
      experimentalFeaturesEnabled: configuration.get(
        "enableExperimentalFeatures",
      ),
      featuresConfiguration: configuration.get("featuresConfiguration"),
      formatter: configuration.get("formatter"),
      linters: configuration.get("linters"),
    },
  };
}

export default class Client extends LanguageClient implements ClientInterface {
  public readonly ruby: Ruby;
  public serverVersion?: string;
  public addons?: Addon[];
  private readonly workingDirectory: string;
  private readonly telemetry: Telemetry;
  private readonly createTestItems: (response: CodeLens[]) => void;
  private readonly baseFolder;
  private requestId = 0;
  private readonly workspaceOutputChannel: WorkspaceChannel;

  #context: vscode.ExtensionContext;
  #formatter: string;

  constructor(
    context: vscode.ExtensionContext,
    telemetry: Telemetry,
    ruby: Ruby,
    createTestItems: (response: CodeLens[]) => void,
    workspaceFolder: vscode.WorkspaceFolder,
    outputChannel: WorkspaceChannel,
    isMainWorkspace = false,
  ) {
    super(
      LSP_NAME,
      getLspExecutables(workspaceFolder, ruby.env),
      collectClientOptions(
        vscode.workspace.getConfiguration("rubyLsp"),
        workspaceFolder,
        outputChannel,
        ruby,
        isMainWorkspace,
      ),
    );

    this.workspaceOutputChannel = outputChannel;

    // Middleware are part of client options, but because they must reference `this`, we cannot make it a part of the
    // `super` call (TypeScript does not allow accessing `this` before invoking `super`)
    this.registerMiddleware();

    this.workingDirectory = workspaceFolder.uri.fsPath;
    this.baseFolder = path.basename(this.workingDirectory);
    this.telemetry = telemetry;
    this.createTestItems = createTestItems;
    this.#context = context;
    this.ruby = ruby;
    this.#formatter = "";
  }

  async afterStart() {
    this.#formatter = this.initializeResult?.formatter;
    this.serverVersion = this.initializeResult?.serverInfo?.version;
    await this.fetchAddons();
  }

  async fetchAddons() {
    if (this.initializeResult?.capabilities.experimental?.addon_detection) {
      try {
        this.addons = await this.sendRequest("rubyLsp/workspace/addons", {});
      } catch (error: any) {
        this.workspaceOutputChannel.error(
          `Error while fetching addons: ${error.data.errorMessage}`,
        );
      }
    }
  }

  get formatter(): string {
    return this.#formatter;
  }

  get context(): vscode.ExtensionContext {
    return this.#context;
  }

  private set context(context: vscode.ExtensionContext) {
    this.#context = context;
  }

  async sendShowSyntaxTreeRequest(
    uri: vscode.Uri,
    range?: Range,
  ): Promise<{ ast: string } | null> {
    return this.sendRequest("rubyLsp/textDocument/showSyntaxTree", {
      textDocument: { uri: uri.toString() },
      range,
    });
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

    const request = typeof type === "string" ? type : type.method;

    // The first few requests are not representative for telemetry. Their response time is much higher than the rest
    // because they are inflate by the time we spend indexing and by regular "warming up" of the server (like
    // autoloading constants or running signature blocks).
    if (this.requestId < 50) {
      this.requestId++;
      return runRequest();
    }

    const telemetryData: RequestEvent = {
      request,
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
    await this.telemetry.sendEvent(telemetryData);

    // If there has been an error, we must throw it again. Otherwise we can return the result
    if (errorResult) {
      if (
        this.baseFolder === "ruby-lsp" ||
        this.baseFolder === "ruby-lsp-rails"
      ) {
        await vscode.window.showErrorMessage(
          `Ruby LSP error ${errorResult.data.errorClass}: ${errorResult.data.errorMessage}\n\n
                ${errorResult.data.backtrace}`,
        );
      }

      throw errorResult;
    }

    return result!;
  }

  // Register the middleware in the client options
  private registerMiddleware() {
    this.clientOptions.middleware = {
      provideCodeLenses: async (document, token, next) => {
        const response = await next(document, token);

        if (response) {
          const testLenses = response.filter(
            (codeLens) => (codeLens as CodeLens).data.type === "test",
          ) as CodeLens[];

          if (testLenses.length) {
            this.createTestItems(testLenses);
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
        const response: vscode.TextEdit[] | null = await this.sendRequest(
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
        const cursorPosition = response.find((edit) => edit.newText === "$0");

        if (!cursorPosition) {
          return response;
        }

        // Remove the edit including the $0 anchor
        response.splice(response.indexOf(cursorPosition), 1);

        const workspaceEdit = new vscode.WorkspaceEdit();
        workspaceEdit.set(document.uri, response);

        const editor = vscode.window.activeTextEditor!;

        // This should happen before applying the edits, otherwise the cursor will be moved to the wrong position
        const existingText = editor.document.lineAt(
          cursorPosition.range.start.line,
        ).text;

        await vscode.workspace.applyEdit(workspaceEdit);

        const indentChar = vscode.window.activeTextEditor?.options.insertSpaces
          ? " "
          : "\t";

        // If the line is not empty, we don't want to indent the cursor
        let indentationLength = 0;

        // If the line is empty or only contains whitespace, we want to indent the cursor to the requested position
        if (/^\s*$/.exec(existingText)) {
          indentationLength = cursorPosition.range.end.character;
        }

        const indentation = indentChar.repeat(indentationLength);

        await vscode.window.activeTextEditor!.insertSnippet(
          new vscode.SnippetString(`${indentation}${cursorPosition.newText}`),
          new vscode.Selection(
            cursorPosition.range.start,
            cursorPosition.range.end,
          ),
        );

        return null;
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
        return this.benchmarkMiddleware(type, params, () => next(type, params));
      },
    };
  }
}
