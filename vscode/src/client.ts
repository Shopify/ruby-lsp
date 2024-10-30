import path from "path";
import os from "os";
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
  ErrorHandler,
  CloseHandlerResult,
  ErrorHandlerResult,
  Message,
  ErrorAction,
  CloseAction,
  State,
  DocumentFilter,
  CompletionList,
  StaticFeature,
  ClientCapabilities,
  FeatureState,
  ServerCapabilities,
  ErrorCodes,
} from "vscode-languageclient/node";

import {
  LSP_NAME,
  ClientInterface,
  Addon,
  SUPPORTED_LANGUAGE_IDS,
} from "./common";
import { Ruby } from "./ruby";
import { WorkspaceChannel } from "./workspaceChannel";

type EnabledFeatures = Record<string, boolean>;

interface ServerErrorTelemetryEvent {
  type: "error";
  errorMessage: string;
  errorClass: string;
  stack: string;
}

type ServerTelemetryEvent = ServerErrorTelemetryEvent;

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
  const useLauncher: boolean = config.get("useLauncher")!;

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
    const args = [];

    if (branch.length > 0) {
      args.push("--branch", branch);
    }

    if (useLauncher) {
      args.push("--use-launcher");
    }

    run = {
      command: "ruby-lsp",
      args,
      options: executableOptions,
    };

    debug = {
      command: "ruby-lsp",
      args: args.concat(["--debug"]),
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
  telemetry: vscode.TelemetryLogger,
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

  // For each workspace, the language client is responsible for handling requests for:
  // 1. Files inside of the workspace itself
  // 2. Bundled gems
  // 3. Default gems
  let documentSelector: DocumentSelector = SUPPORTED_LANGUAGE_IDS.map(
    (language) => {
      return { language, pattern: `${fsPath}/**/*` };
    },
  );

  // Only the first language server we spawn should handle unsaved files, otherwise requests will be duplicated across
  // all workspaces
  if (isMainWorkspace) {
    SUPPORTED_LANGUAGE_IDS.forEach((language) => {
      documentSelector.push({
        language,
        scheme: "untitled",
      });
    });
  }

  ruby.gemPath.forEach((gemPath) => {
    documentSelector.push({
      language: "ruby",
      pattern: `${gemPath}/**/*`,
    });

    // Because of how default gems are installed, the gemPath location is actually not exactly where the files are
    // located. With the regex, we are correcting the default gem path from this (where the files are not located)
    // /opt/rubies/3.3.1/lib/ruby/gems/3.3.0
    //
    // to this (where the files are actually stored)
    // /opt/rubies/3.3.1/lib/ruby/3.3.0
    //
    // Notice that we still need to add the regular path to the selector because some version managers will install gems
    // under the non-corrected path
    if (/lib\/ruby\/gems\/(?=\d)/.test(gemPath)) {
      documentSelector.push({
        language: "ruby",
        pattern: `${gemPath.replace(/lib\/ruby\/gems\/(?=\d)/, "lib/ruby/")}/**/*`,
      });
    }
  });

  // This is a temporary solution as an escape hatch for users who cannot upgrade the `ruby-lsp` gem to a version that
  // supports ERB
  if (!configuration.get<boolean>("erbSupport")) {
    documentSelector = documentSelector.filter((selector) => {
      return (selector as DocumentFilter).language !== "erb";
    });
  }

  return {
    documentSelector,
    workspaceFolder,
    diagnosticCollectionName: LSP_NAME,
    outputChannel,
    revealOutputChannelOn: RevealOutputChannelOn.Never,
    diagnosticPullOptions,
    errorHandler: new ClientErrorHandler(workspaceFolder, telemetry),
    initializationOptions: {
      enabledFeatures,
      experimentalFeaturesEnabled: configuration.get(
        "enableExperimentalFeatures",
      ),
      featuresConfiguration: configuration.get("featuresConfiguration"),
      formatter: configuration.get("formatter"),
      linters: configuration.get("linters"),
      indexing: configuration.get("indexing"),
      addonSettings: configuration.get("addonSettings"),
    },
  };
}

class ClientErrorHandler implements ErrorHandler {
  private readonly workspaceFolder: vscode.WorkspaceFolder;
  private readonly telemetry: vscode.TelemetryLogger;

  constructor(
    workspaceFolder: vscode.WorkspaceFolder,
    telemetry: vscode.TelemetryLogger,
  ) {
    this.workspaceFolder = workspaceFolder;
    this.telemetry = telemetry;
  }

  error(
    _error: Error,
    _message: Message | undefined,
    _count: number | undefined,
  ): ErrorHandlerResult | Promise<ErrorHandlerResult> {
    return { action: ErrorAction.Shutdown, handled: true };
  }

  async closed(): Promise<CloseHandlerResult> {
    const label = vscode.workspace
      .getConfiguration("rubyLsp")
      .get("useLauncher")
      ? "launcher"
      : "direct";

    this.telemetry.logUsage("ruby_lsp.launch_failure", {
      type: "counter",
      attributes: {
        label,
      },
    });

    const answer = await vscode.window.showErrorMessage(
      `Launching the Ruby LSP failed. This typically happens due to an error with version manager
      integration or Bundler issues.

      [Logs](command:workbench.action.output.toggleOutput) |
      [Troubleshooting](https://shopify.github.io/ruby-lsp/troubleshooting.html) |
      [Run bundle install](command:rubyLsp.bundleInstall?"${this.workspaceFolder.uri.toString()}")`,
      "Retry",
      "Shutdown",
    );

    if (answer === "Retry") {
      return { action: CloseAction.Restart, handled: true };
    }

    return { action: CloseAction.DoNotRestart, handled: true };
  }
}

// This class is used to populate custom client capabilities, so that they are sent as part of the initialize request to
// the server. This can be used to ensure that custom functionality is properly synchronized with the server
class ExperimentalCapabilities implements StaticFeature {
  fillClientCapabilities(capabilities: ClientCapabilities): void {
    capabilities.experimental = {
      requestDelegation: true,
    };
  }

  initialize(
    _capabilities: ServerCapabilities,
    _documentSelector: DocumentSelector | undefined,
  ): void {}

  getState(): FeatureState {
    return { kind: "static" };
  }

  clear(): void {}
}

export default class Client extends LanguageClient implements ClientInterface {
  public readonly ruby: Ruby;
  public serverVersion?: string;
  public addons?: Addon[];
  public degraded = false;
  private readonly workingDirectory: string;
  private readonly telemetry: vscode.TelemetryLogger;
  private readonly createTestItems: (response: CodeLens[]) => void;
  private readonly baseFolder;
  private readonly workspaceOutputChannel: WorkspaceChannel;
  private readonly virtualDocuments = new Map<string, string>();

  #context: vscode.ExtensionContext;
  #formatter: string;

  constructor(
    context: vscode.ExtensionContext,
    telemetry: vscode.TelemetryLogger,
    ruby: Ruby,
    createTestItems: (response: CodeLens[]) => void,
    workspaceFolder: vscode.WorkspaceFolder,
    outputChannel: WorkspaceChannel,
    virtualDocuments: Map<string, string>,
    isMainWorkspace = false,
    debugMode?: boolean,
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
        telemetry,
      ),
      debugMode,
    );

    this.registerFeature(new ExperimentalCapabilities());
    this.workspaceOutputChannel = outputChannel;
    this.virtualDocuments = virtualDocuments;

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

    // When the server processes changes to an ERB document, it will send this custom notification to update the state
    // of the virtual documents
    this.onNotification("delegate/textDocument/virtualState", (params) => {
      this.virtualDocuments.set(
        params.textDocument.uri,
        params.textDocument.text,
      );
    });

    this.onTelemetry((event: ServerTelemetryEvent) => {
      if (event.type === "error") {
        this.telemetry.logError(
          {
            message: event.errorMessage,
            name: event.errorClass,
            stack: event.stack,
          },
          { serverVersion: this.serverVersion },
        );
      }
    });
  }

  async afterStart() {
    this.#formatter = this.initializeResult?.formatter;
    this.serverVersion = this.initializeResult?.serverInfo?.version;

    if (this.initializeResult?.degraded_mode) {
      this.degraded = this.initializeResult?.degraded_mode;
    }

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
    if (this.state !== State.Running) {
      return runRequest();
    }

    const request = typeof type === "string" ? type : type.method;

    try {
      // Execute the request measuring the time it takes to receive the response
      Perf.mark(`${request}.start`);
      const result = await runRequest();
      Perf.mark(`${request}.end`);

      const bench = Perf.measure(
        "benchmarks",
        `${request}.start`,
        `${request}.end`,
      );

      this.logResponseTime(bench.duration, request);
      return result;
    } catch (error: any) {
      // We use a special error code to indicate delegated requests. This is not actually an error, it's a signal that
      // the client needs to invoke the appropriate language service for this request
      if (error.code === -32900) {
        return this.executeDelegateRequest(type, params);
      }

      if (error.data) {
        if (
          this.baseFolder === "ruby-lsp" ||
          this.baseFolder === "ruby-lsp-rails"
        ) {
          await vscode.window.showErrorMessage(
            `Ruby LSP error ${error.data.errorClass}: ${error.data.errorMessage}\n\n${error.data.backtrace}`,
          );
        } else {
          const { errorMessage, errorClass, backtrace } = error.data;

          // We only want to produce telemetry events for errors that have all the data we need and that are internal
          // server errors. Other errors do not necessarily indicate bugs in the server. You can check LSP error codes
          // here https://microsoft.github.io/language-server-protocol/specification/#errorCodes
          if (
            errorMessage &&
            errorClass &&
            backtrace &&
            error.code === ErrorCodes.InternalError
          ) {
            // Sanitize the backtrace coming from the server to remove the user's home directory from it, then mark it
            // as a trusted value. Otherwise the VS Code telemetry logger redacts the entire backtrace and we are unable
            // to see where in the server the error occurred
            const stack = new vscode.TelemetryTrustedValue(
              backtrace
                .split("\n")
                .map((line: string) => line.replace(os.homedir(), "~"))
                .join("\n"),
            ) as any;

            this.telemetry.logError(
              {
                message: errorMessage,
                name: errorClass,
                stack,
              },
              {
                ...error.data,
                serverVersion: this.serverVersion,
                workspace: new vscode.TelemetryTrustedValue(
                  this.workingDirectory,
                ),
              },
            );
          }
        }
      }

      throw error;
    }
  }

  // Delegate a request to the appropriate language service. Note that only position based requests are delegated here.
  // Full file requests, such as folding range, have their own separate middleware to merge the embedded Ruby + host
  // language responses
  private async executeDelegateRequest(
    type: string | MessageSignature,
    params: any,
  ): Promise<any> {
    const request = typeof type === "string" ? type : type.method;
    const originalUri = params.textDocument.uri;

    // Delegating requests only makes sense for text document requests, where a URI is available
    if (!originalUri) {
      return null;
    }

    // To delegate requests, we use a special URI scheme so that VS Code can delegate to the correct provider. For an
    // `index.html.erb` file, the URI would look like `embedded-content://html/file:///index.html.erb.html`
    const virtualDocumentUri = this.virtualDocumentUri(originalUri);

    // Call the appropriate language service for the request, so that VS Code delegates the work accordingly
    switch (request) {
      case "textDocument/completion":
        return vscode.commands
          .executeCommand<CompletionList>(
            "vscode.executeCompletionItemProvider",
            vscode.Uri.parse(virtualDocumentUri),
            params.position,
            params.context.triggerCharacter,
          )
          .then((response) => {
            // We need to tell the server that the completion item is being delegated, so that when it receives the
            // `completionItem/resolve`, we can delegate that too
            response.items.forEach((item) => {
              // For whatever reason, HTML completion items don't include the `kind` and that causes a failure in the
              // editor. It might be a mistake in the delegation
              if (
                item.documentation &&
                typeof item.documentation !== "string" &&
                "value" in item.documentation
              ) {
                item.documentation.kind = "markdown";
              }

              item.data = { ...item.data, delegateCompletion: true };
            });

            return response;
          });
      case "textDocument/hover":
        return vscode.commands.executeCommand(
          "vscode.executeHoverProvider",
          vscode.Uri.parse(virtualDocumentUri),
          params.position,
        );
      case "textDocument/definition":
        return vscode.commands.executeCommand(
          "vscode.executeDefinitionProvider",
          vscode.Uri.parse(virtualDocumentUri),
          params.position,
        );
      case "textDocument/signatureHelp":
        return vscode.commands.executeCommand(
          "vscode.executeSignatureHelpProvider",
          vscode.Uri.parse(virtualDocumentUri),
          params.position,
          params.context?.triggerCharacter,
        );
      case "textDocument/documentHighlight":
        return vscode.commands.executeCommand(
          "vscode.executeDocumentHighlights",
          vscode.Uri.parse(virtualDocumentUri),
          params.position,
        );
      default:
        this.workspaceOutputChannel.warn(
          `Attempted to delegate unsupported request ${request}`,
        );
        return null;
    }
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
      didClose: (textDocument, next) => {
        // Delete virtual ERB host language documents if they exist and then proceed to the next middleware to fire the
        // request to the server
        this.virtualDocuments.delete(textDocument.uri.toString(true));
        return next(textDocument);
      },
      // **** Full document request delegation middleware below ****
      provideFoldingRanges: async (document, context, token, next) => {
        if (document.languageId === "erb") {
          const virtualDocumentUri = this.virtualDocumentUri(
            document.uri.toString(true),
          );

          // Execute folding range for the host language
          const hostResponse = await vscode.commands.executeCommand<
            vscode.FoldingRange[]
          >(
            "vscode.executeFoldingRangeProvider",
            vscode.Uri.parse(virtualDocumentUri),
          );

          // Execute folding range for the embedded Ruby
          const rubyResponse = await next(document, context, token);
          return hostResponse.concat(rubyResponse ?? []);
        }

        return next(document, context, token);
      },
      provideDocumentLinks: async (document, token, next) => {
        if (document.languageId === "erb") {
          const virtualDocumentUri = this.virtualDocumentUri(
            document.uri.toString(true),
          );

          // Execute document links for the host language
          const hostResponse = await vscode.commands.executeCommand<
            vscode.DocumentLink[]
          >("vscode.executeLinkProvider", vscode.Uri.parse(virtualDocumentUri));

          // Execute document links for the embedded Ruby
          const rubyResponse = await next(document, token);
          return hostResponse.concat(rubyResponse ?? []);
        }

        return next(document, token);
      },
    };
  }

  private virtualDocumentUri(originalUri: string) {
    const hostLanguage = /\.([^.]+)\.erb$/.exec(originalUri)?.[1] || "html";
    return `embedded-content://${hostLanguage}/${encodeURIComponent(
      originalUri,
    )}.${hostLanguage}`;
  }

  private logResponseTime(duration: number, label: string) {
    this.telemetry.logUsage("ruby_lsp.response_time", {
      type: "histogram",
      value: duration,
      attributes: {
        message: new vscode.TelemetryTrustedValue(label),
        lspVersion: this.serverVersion,
        rubyVersion: this.ruby.rubyVersion,
      },
    });
  }
}
