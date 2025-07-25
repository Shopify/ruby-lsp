import * as os from "os";
import * as path from "path";

import * as vscode from "vscode";
import { Range } from "vscode-languageclient/node";

import DocumentProvider from "./documentProvider";
import { Workspace } from "./workspace";
import { Command, featureEnabled, LOG_CHANNEL, STATUS_EMITTER, SUPPORTED_LANGUAGE_IDS } from "./common";
import { ManagerIdentifier, ManagerConfiguration } from "./ruby";
import { StatusItems } from "./status";
import { TestController } from "./testController";
import { newMinitestFile, openFile, openUris } from "./commands";
import { Debugger } from "./debugger";
import { DependenciesTree } from "./dependenciesTree";
import { Rails } from "./rails";
import { ChatAgent } from "./chatAgent";
import { collectRubyLspInfo } from "./infoCollector";
import { Mode } from "./streamingRunner";

// The RubyLsp class represents an instance of the entire extension. This should only be instantiated once at the
// activation event. One instance of this class controls all of the existing workspaces, telemetry and handles all
// commands
export class RubyLsp {
  private readonly workspaces: Map<string, Workspace> = new Map();
  private readonly context: vscode.ExtensionContext;
  private readonly statusItems: StatusItems;
  private readonly testController: TestController;
  private readonly debug: Debugger;
  private readonly telemetry: vscode.TelemetryLogger;
  private readonly rails: Rails;

  // A URI => content map of virtual documents for delegate requests
  private readonly virtualDocuments = new Map<string, string>();
  private readonly workspacesBeingLaunched = new Map<number, Promise<Workspace | undefined>>();

  constructor(context: vscode.ExtensionContext, telemetry: vscode.TelemetryLogger) {
    this.context = context;
    this.telemetry = telemetry;
    this.testController = new TestController(
      context,
      this.telemetry,
      this.currentActiveWorkspace.bind(this),
      this.getOrActivateWorkspace.bind(this),
    );
    this.debug = new Debugger(context, this.workspaceResolver.bind(this));
    this.rails = new Rails(this.showWorkspacePick.bind(this));

    this.statusItems = new StatusItems();
    const dependenciesTree = new DependenciesTree();
    context.subscriptions.push(
      this.statusItems,
      this.debug,
      dependenciesTree,
      new ChatAgent(context, this.showWorkspacePick.bind(this)),

      // Switch the status items based on which workspace is currently active
      vscode.window.onDidChangeActiveTextEditor((editor) => {
        STATUS_EMITTER.fire(this.currentActiveWorkspace(editor));
      }),
      vscode.workspace.onDidChangeWorkspaceFolders(async (event) => {
        // Stop the language server and dispose all removed workspaces
        for (const workspaceFolder of event.removed) {
          const workspace = this.getWorkspace(workspaceFolder.uri);

          if (workspace) {
            await workspace.stop();
            await workspace.dispose();
            this.workspaces.delete(workspaceFolder.uri.toString());
          }
        }
      }),
      // Lazily activate workspaces that do not contain a lockfile
      vscode.workspace.onDidOpenTextDocument(async (document) => {
        if (!SUPPORTED_LANGUAGE_IDS.includes(document.languageId)) {
          return;
        }

        const workspaceFolder = vscode.workspace.getWorkspaceFolder(document.uri);

        if (!workspaceFolder) {
          return;
        }

        const workspace = this.getWorkspace(workspaceFolder.uri);

        // If the workspace entry doesn't exist, then we haven't activated the workspace yet
        if (!workspace) {
          await this.activateWorkspace(workspaceFolder, false);
        }
      }),
      vscode.workspace.registerTextDocumentContentProvider("embedded-content", {
        provideTextDocumentContent: (uri) => {
          // For embedded content, we store it as a virtual file using the original URI as the key. We need to extract
          // some parts of the custom URI to get the original URI
          const originalUri = /^\/(.*)\.[^.]+$/.exec(uri.path)?.[1];

          if (!originalUri) {
            return "";
          }

          const decodedUri = decodeURIComponent(originalUri);
          return this.virtualDocuments.get(decodedUri);
        },
      }),
      LOG_CHANNEL,
      vscode.workspace.registerTextDocumentContentProvider("ruby-lsp", new DocumentProvider()),
      ...this.registerCommands(),
    );
  }

  // Activate the extension. This method should perform all actions necessary to start the extension, such as booting
  // all language servers for each existing workspace
  async activate() {
    await vscode.commands.executeCommand("testing.clearTestResults");

    const firstWorkspace = vscode.workspace.workspaceFolders?.[0];

    // We only activate the first workspace eagerly to avoid running into performance and memory issues. Having too many
    // workspaces spawning the Ruby LSP server and indexing can grind the editor to a halt. All other workspaces are
    // activated lazily once a Ruby document is opened inside of it through the `onDidOpenTextDocument` event
    if (firstWorkspace) {
      await this.activateWorkspace(firstWorkspace, true);
    }

    // If the user has the editor already opened on a Ruby file and that file does not belong to the first workspace,
    // eagerly activate the workspace for that file too
    const activeDocument = vscode.window.activeTextEditor?.document;

    if (activeDocument && SUPPORTED_LANGUAGE_IDS.includes(activeDocument.languageId)) {
      const workspaceFolder = vscode.workspace.getWorkspaceFolder(activeDocument.uri);

      if (workspaceFolder) {
        const existingWorkspace = this.workspaces.get(workspaceFolder.uri.toString());

        if (!existingWorkspace) {
          await this.activateWorkspace(workspaceFolder, false);
        }
      }
    }

    STATUS_EMITTER.fire(this.currentActiveWorkspace());
    await this.testController.activate();
  }

  // Deactivate the extension, which should stop all language servers. Notice that this just stops anything that is
  // running, but doesn't dispose of existing instances
  async deactivate() {
    for (const workspace of this.workspaces.values()) {
      await workspace.stop();
      await workspace.dispose();
    }
  }

  // Overloaded signatures because when the workspace activation is lazy, it is guaranteed to return `Workspace`, which
  // avoids checking for undefined in the caller
  private async activateWorkspace(workspaceFolder: vscode.WorkspaceFolder, eager: true): Promise<Workspace | undefined>;

  private async activateWorkspace(workspaceFolder: vscode.WorkspaceFolder, eager: false): Promise<Workspace>;

  private async activateWorkspace(
    workspaceFolder: vscode.WorkspaceFolder,
    eager: boolean,
  ): Promise<Workspace | undefined> {
    const existingActivationPromise = this.workspacesBeingLaunched.get(workspaceFolder.index);
    if (existingActivationPromise) {
      return existingActivationPromise;
    }

    const activationPromise = this.runActivation(workspaceFolder, eager);
    this.workspacesBeingLaunched.set(workspaceFolder.index, activationPromise);
    return activationPromise;
  }

  private async runActivation(workspaceFolder: vscode.WorkspaceFolder, eager: boolean) {
    const customBundleGemfile: string = vscode.workspace.getConfiguration("rubyLsp").get("bundleGemfile")!;

    const lockfileExists = await this.lockfileExists(workspaceFolder.uri);

    // When eagerly activating workspaces, we skip the ones that do not have a lockfile since they may not be a Ruby
    // workspace. Those cases are activated lazily below
    if (eager && !lockfileExists) {
      this.workspacesBeingLaunched.delete(workspaceFolder.index);
      return;
    }

    // If no lockfile exists and we're activating lazily (if the user opened a Ruby file inside a workspace we hadn't
    // activated before), then we start the language server, but we warn the user that they may be missing multi-root
    // workspace configuration
    if (customBundleGemfile.length === 0 && !lockfileExists) {
      await this.showStandaloneWarning(workspaceFolder.uri.fsPath);
    }

    const workspace = new Workspace(
      this.context,
      workspaceFolder,
      this.telemetry,
      this.testController.createTestItems.bind(this.testController),
      this.virtualDocuments,
      this.workspaces.size === 0,
    );

    await workspace.activate();
    await workspace.start();

    this.workspaces.set(workspaceFolder.uri.toString(), workspace);

    // If we successfully activated a workspace, then we can start showing the dependencies tree view. This is necessary
    // so that we can avoid showing it on non Ruby projects
    await vscode.commands.executeCommand("setContext", "rubyLsp.activated", true);
    await this.showFormatOnSaveModeWarning(workspace);
    this.workspacesBeingLaunched.delete(workspaceFolder.index);
    return workspace;
  }

  // Registers all extension commands. Commands can only be registered once, so this happens in the constructor. For
  // creating multiple instances in tests, the `RubyLsp` object should be disposed of after each test to prevent double
  // command register errors
  private registerCommands(): vscode.Disposable[] {
    return [
      vscode.commands.registerCommand(Command.Update, async () => {
        const workspace = await this.showWorkspacePick();

        if (workspace) {
          await workspace.installOrUpdateServer(true);
          await workspace.restart();
        }
      }),
      vscode.commands.registerCommand(Command.Start, async () => {
        const workspace = await this.showWorkspacePick();
        await workspace?.start();
      }),
      vscode.commands.registerCommand(Command.Restart, async () => {
        const workspace = await this.showWorkspacePick();
        await workspace?.restart();
      }),
      vscode.commands.registerCommand(Command.Stop, async () => {
        const workspace = await this.showWorkspacePick();
        await workspace?.dispose();
      }),
      vscode.commands.registerCommand(Command.ShowSyntaxTree, this.showSyntaxTree.bind(this)),
      vscode.commands.registerCommand(Command.DiagnoseState, this.diagnoseState.bind(this)),
      vscode.commands.registerCommand(Command.ShowServerChangelog, () => {
        const version = this.currentActiveWorkspace()?.lspClient?.serverVersion;

        if (!version) {
          return;
        }
        return vscode.env.openExternal(
          vscode.Uri.parse(`https://github.com/Shopify/ruby-lsp/releases/tag/v${version}`),
        );
      }),
      vscode.commands.registerCommand(Command.FormatterHelp, () => {
        return vscode.env.openExternal(
          vscode.Uri.parse("https://github.com/Shopify/ruby-lsp/blob/main/vscode/README.md#formatting"),
        );
      }),
      vscode.commands.registerCommand(Command.DisplayAddons, () => {
        const client = this.currentActiveWorkspace()?.lspClient;

        if (!client || !client.addons) {
          return;
        }

        const options: vscode.QuickPickItem[] = client.addons
          .sort((addon) => (addon.errored ? 1 : -1))
          .map((addon) => {
            const icon = addon.errored ? "$(error)" : "$(pass)";
            return {
              label: `${icon} ${addon.name} ${addon.version ? `v${addon.version}` : ""}`,
            };
          });

        const quickPick = vscode.window.createQuickPick();
        quickPick.items = options;
        quickPick.placeholder = "Addons (click to view output)";

        quickPick.onDidAccept(() => {
          const selected = quickPick.selectedItems[0];
          // Ideally, we should display information that's specific to the selected addon
          if (selected) {
            this.currentActiveWorkspace()?.outputChannel.show();
          }
          quickPick.hide();
        });

        quickPick.onDidHide(() => {
          quickPick.dispose();
        });

        quickPick.show();
      }),
      vscode.commands.registerCommand(Command.ToggleFeatures, async () => {
        // Extract feature descriptions from our package.json
        const enabledFeaturesProperties =
          vscode.extensions.getExtension("Shopify.ruby-lsp")!.packageJSON.contributes.configuration.properties[
            "rubyLsp.enabledFeatures"
          ].properties;

        const descriptions: Record<string, string> = {};
        Object.entries(enabledFeaturesProperties).forEach(([key, value]: [string, any]) => {
          descriptions[key] = value.description;
        });

        const configuration = vscode.workspace.getConfiguration("rubyLsp");
        const features: Record<string, boolean> = configuration.get("enabledFeatures")!;
        const allFeatures = Object.keys(features);
        const options: vscode.QuickPickItem[] = allFeatures.map((label) => {
          return {
            label,
            picked: features[label],
            description: descriptions[label],
          };
        });

        const toggledFeatures = await vscode.window.showQuickPick(options, {
          canPickMany: true,
          placeHolder: "Select the features you would like to enable",
        });

        if (toggledFeatures !== undefined) {
          // The `picked` property is only used to determine if the checkbox is checked initially. When we receive the
          // response back from the QuickPick, we need to use inclusion to check if the feature was selected
          allFeatures.forEach((feature) => {
            features[feature] = toggledFeatures.some((selected) => selected.label === feature);
          });

          await vscode.workspace.getConfiguration("rubyLsp").update("enabledFeatures", features, true, true);
        }
      }),
      vscode.commands.registerCommand(Command.ToggleExperimentalFeatures, async () => {
        const lspConfig = vscode.workspace.getConfiguration("rubyLsp");
        const experimentalFeaturesEnabled = lspConfig.get("enableExperimentalFeatures");
        await lspConfig.update("enableExperimentalFeatures", !experimentalFeaturesEnabled, true, true);

        STATUS_EMITTER.fire(this.currentActiveWorkspace());
      }),
      vscode.commands.registerCommand(
        Command.ServerOptions,
        async (options: [{ label: string; description: string }]) => {
          const result = await vscode.window.showQuickPick(options, {
            placeHolder: "Select server action",
          });

          if (result !== undefined) await vscode.commands.executeCommand(result.description);
        },
      ),
      vscode.commands.registerCommand(Command.SelectVersionManager, async () => {
        const answer = await vscode.window.showQuickPick(
          ["Change version manager", "Change manual Ruby configuration"],
          { placeHolder: "What would you like to do?" },
        );

        if (!answer) {
          return;
        }

        if (answer === "Change version manager") {
          const configuration = vscode.workspace.getConfiguration("rubyLsp");
          const managerConfig = configuration.get<ManagerConfiguration>("rubyVersionManager")!;
          const options = Object.values(ManagerIdentifier);
          const manager = (await vscode.window.showQuickPick(options, {
            placeHolder: `Current: ${managerConfig.identifier}`,
          })) as ManagerIdentifier | undefined;

          if (manager !== undefined) {
            managerConfig.identifier = manager;
            await configuration.update("rubyVersionManager", managerConfig, true);
          }

          return;
        }

        const workspace = await this.showWorkspacePick();

        if (!workspace) {
          return;
        }

        await workspace.ruby.manuallySelectRuby();
      }),
      vscode.commands.registerCommand(Command.RunTest, (path, name, _command) => {
        return featureEnabled("fullTestDiscovery")
          ? this.testController.runViaCommand(path, name, Mode.Run)
          : this.testController.runOnClick(name);
      }),
      vscode.commands.registerCommand(Command.RunTestInTerminal, (path, name, command) => {
        return featureEnabled("fullTestDiscovery")
          ? this.testController.runViaCommand(path, name, Mode.RunInTerminal)
          : this.testController.runTestInTerminal(path, name, command);
      }),
      vscode.commands.registerCommand(Command.DebugTest, (path, name, command) => {
        return featureEnabled("fullTestDiscovery")
          ? this.testController.runViaCommand(path, name, Mode.Debug)
          : this.testController.debugTest(path, name, command);
      }),
      vscode.commands.registerCommand(Command.RunTask, async (command: string) => {
        let workspace = this.currentActiveWorkspace();

        if (!workspace) {
          workspace = await this.showWorkspacePick();
        }

        if (!workspace) {
          return;
        }

        await workspace.execute(command, true);
      }),
      vscode.commands.registerCommand(Command.BundleInstall, (workspaceUri: string) => {
        const workspace = this.workspaces.get(workspaceUri);

        if (!workspace) {
          return;
        }

        const terminal = vscode.window.createTerminal({
          name: "Bundle install",
          cwd: workspace.workspaceFolder.uri.fsPath,
          env: workspace.ruby.env,
        });

        terminal.show();
        terminal.sendText("bundle install");
      }),
      vscode.commands.registerCommand(Command.OpenFile, (rubySourceLocation: [string, string] | string[]) => {
        // New command format: accepts an array of URIs
        if (typeof rubySourceLocation[0] === "string") {
          return openUris(rubySourceLocation);
        }

        // Old format: we can remove after the Rails add-on has been using the new format for a while
        const [file, line] = rubySourceLocation;
        const workspace = this.currentActiveWorkspace();
        return openFile(this.telemetry, workspace, {
          file,
          line: parseInt(line, 10) - 1,
        });
      }),
      vscode.commands.registerCommand(
        Command.RailsGenerate,
        async (generatorWithArguments: string | string[] | undefined, workspace: Workspace | undefined) => {
          // If the command was invoked programmatically, then the arguments will already be present. Otherwise, we need
          // to show a UI so that the user can pick the arguments to generate
          const command =
            generatorWithArguments ??
            (await vscode.window.showInputBox({
              title: "Rails generate arguments",
              placeHolder: "model User name:string | scaffold Post title:string",
            }));

          if (!command) {
            return;
          }

          if (typeof command === "string") {
            await this.rails.generate(command, workspace);
            return;
          }

          for (const generate of command) {
            await this.rails.generate(generate, workspace);
          }
        },
      ),
      vscode.commands.registerCommand(
        Command.RailsDestroy,
        async (generatorWithArguments: string | string[] | undefined, workspace: Workspace | undefined) => {
          // If the command was invoked programmatically, then the arguments will already be present. Otherwise, we need
          // to show a UI so that the user can pick the arguments to destroy
          const command =
            generatorWithArguments ??
            (await vscode.window.showInputBox({
              title: "Rails destroy arguments",
              placeHolder: "model User name:string | scaffold Post title:string",
            }));

          if (!command) {
            return;
          }

          if (typeof command === "string") {
            await this.rails.destroy(command, workspace);
            return;
          }

          for (const generate of command) {
            await this.rails.destroy(generate, workspace);
          }
        },
      ),
      vscode.commands.registerCommand(Command.FileOperation, async () => {
        const workspace = await this.showWorkspacePick();

        if (!workspace) {
          return;
        }

        const items: ({
          command: string;
          args: any[];
        } & vscode.QuickPickItem)[] = [
          {
            label: "Minitest test",
            description: "Create a new Minitest test",
            iconPath: new vscode.ThemeIcon("new-file"),
            command: Command.NewMinitestFile,
            args: [],
          },
        ];

        if (workspace.lspClient?.addons?.some((addon) => addon.name === "Ruby LSP Rails")) {
          items.push(
            {
              label: "Rails generate",
              description: "Run Rails generate",
              iconPath: new vscode.ThemeIcon("new-file"),
              command: Command.RailsGenerate,
              args: [undefined, workspace],
            },
            {
              label: "Rails destroy",
              description: "Run Rails destroy",
              iconPath: new vscode.ThemeIcon("trash"),
              command: Command.RailsDestroy,
              args: [undefined, workspace],
            },
          );
        }

        const pick = await vscode.window.showQuickPick(items, {
          title: "Select a Ruby file operation",
        });

        if (!pick) {
          return;
        }

        await vscode.commands.executeCommand(pick.command, ...pick.args);
      }),
      vscode.commands.registerCommand(Command.NewMinitestFile, newMinitestFile),
      vscode.commands.registerCommand(Command.CollectRubyLspInfo, async () => {
        const workspace = await this.showWorkspacePick();
        await collectRubyLspInfo(workspace);
      }),
      vscode.commands.registerCommand(Command.StartServerInDebugMode, async () => {
        const workspace = await this.showWorkspacePick();
        await workspace?.start(true);
      }),
      vscode.commands.registerCommand(Command.ShowOutput, () => {
        LOG_CHANNEL.show();
      }),
      vscode.commands.registerCommand(Command.MigrateLaunchConfiguration, async () => {
        const workspace = await this.showWorkspacePick();

        if (!workspace) {
          return;
        }

        const launchConfig = (vscode.workspace.getConfiguration("launch")?.get("configurations") as any[]) || [];

        const updatedLaunchConfig = launchConfig.map((config: any) => {
          if (config.type === "rdbg") {
            if (config.request === "launch") {
              const newConfig: {
                command?: string;
                script?: string;
                args?: string[];
                type?: string;
                askParameters?: boolean;
                useBundler?: boolean;
                rdbgPath?: string;
                cwd?: string;
                program?: string;
              } = { ...config };
              newConfig.type = "ruby_lsp";

              if (newConfig.askParameters !== true) {
                delete newConfig.rdbgPath;
                delete newConfig.cwd;
                delete newConfig.useBundler;

                const command = (newConfig.command ?? "").replace(`\${workspaceRoot}/`, "");
                const script = newConfig.script ?? "";
                const args = (newConfig.args ?? []).join(" ");
                newConfig.program = `${command} ${script} ${args}`.trim();

                delete newConfig.command;
                delete newConfig.script;
                delete newConfig.args;
                delete newConfig.askParameters;
              }

              return newConfig;
            } else if (config.request === "attach") {
              const newConfig = { ...config };
              newConfig.type = "ruby_lsp";
              // rdbg's `debugPort` could be a socket path, or port number, or host:port
              // we don't do complex parsing here, just assume it's socket path
              newConfig.debugSocketPath = config.debugPort;

              return newConfig;
            }
          }
          return config;
        });

        await vscode.workspace
          .getConfiguration("launch")
          .update("configurations", updatedLaunchConfig, vscode.ConfigurationTarget.Workspace);
      }),
      vscode.commands.registerCommand(Command.GoToRelevantFile, async () => {
        const uri = vscode.window.activeTextEditor?.document.uri;
        if (!uri) {
          return;
        }
        const response: { locations: string[] } | null | undefined =
          await this.currentActiveWorkspace()?.lspClient?.sendGoToRelevantFileRequest(uri);

        if (response && response.locations.length > 0) {
          return openUris(response.locations);
        } else {
          await vscode.window.showInformationMessage("Couldn't find relevant files");
        }
      }),
      vscode.commands.registerCommand(Command.ProfileCurrentFile, async () => {
        const workspace = this.currentActiveWorkspace();

        if (!workspace) {
          vscode.window.showInformationMessage("No workspace found");
          return;
        }

        try {
          const { stdout } = await workspace.execute("vernier --version");
          const version = stdout.trim();
          const [major, minor, _] = version.split(".").map(Number);

          if (major < 1 || (major === 1 && minor < 8)) {
            const install = await vscode.window.showInformationMessage(
              "Vernier version 1.8.0 or higher is required for profiling. Would you like to install it?",
              "Install",
            );

            if (install === "Install") {
              await workspace.execute("gem install vernier");
            } else {
              return;
            }
          }
        } catch (_error) {
          const install = await vscode.window.showInformationMessage(
            "Vernier is required for profiling. Would you like to install it?",
            "Install",
          );

          if (install === "Install") {
            await workspace.execute("gem install vernier");
          } else {
            return;
          }
        }

        const currentFile = vscode.window.activeTextEditor?.document.uri.fsPath;

        if (!currentFile) {
          vscode.window.showInformationMessage("No file opened in the editor to profile");
          return;
        }

        await vscode.window.withProgress(
          {
            location: vscode.ProgressLocation.Notification,
            title: "Profiling in progress...",
            cancellable: false,
          },
          async () => {
            const profileUri = vscode.Uri.file(path.join(os.tmpdir(), `profile-${Date.now()}.cpuprofile`));

            await workspace.execute(
              `vernier run --output ${profileUri.fsPath} --format cpuprofile -- ruby ${currentFile}`,
            );

            await vscode.commands.executeCommand("vscode.open", profileUri, {
              viewColumn: vscode.ViewColumn.Beside,
            });
          },
        );
      }),
    ];
  }

  // Get the current active workspace based on which file is opened in the editor
  private currentActiveWorkspace(activeEditor = vscode.window.activeTextEditor): Workspace | undefined {
    let workspaceFolder: vscode.WorkspaceFolder | undefined;

    if (activeEditor) {
      workspaceFolder = vscode.workspace.getWorkspaceFolder(activeEditor.document.uri);
    } else {
      // If there's no active editor, we search based on the current workspace name
      workspaceFolder = vscode.workspace.workspaceFolders?.find((folder) => folder.name === vscode.workspace.name);
    }

    if (!workspaceFolder) {
      return;
    }

    return this.getWorkspace(workspaceFolder.uri);
  }

  private async getOrActivateWorkspace(workspaceFolder: vscode.WorkspaceFolder): Promise<Workspace> {
    const workspace = this.getWorkspace(workspaceFolder.uri);

    if (workspace) {
      return workspace;
    }

    return vscode.window.withProgress(
      {
        location: vscode.ProgressLocation.Notification,
        title: `Workspace ${workspaceFolder.name} is not activated yet.`,
      },
      async (progress) => {
        progress.report({ message: "Activating workspace..." });
        return this.activateWorkspace(workspaceFolder, false);
      },
    );
  }

  private getWorkspace(uri: vscode.Uri): Workspace | undefined {
    return this.workspaces.get(uri.toString());
  }

  private workspaceResolver(uri: vscode.Uri | undefined): Workspace | undefined {
    // If no URI is passed, we try to figured out what the active workspace is
    if (!uri) {
      return this.currentActiveWorkspace();
    }

    // If a workspace is found for that URI, then we return that one
    const workspace = this.workspaces.get(uri.toString());
    if (workspace) {
      return workspace;
    }

    // Otherwise, if there's a URI, but we can't find a workspace for it, we fallback to trying to figure out what the
    // active workspace is. This situation may happen if we receive a workspace folder URI that is not the actual
    // workspace where the Ruby application exists. For example, if you have a monorepo with client and server
    // directories and the `launch.json` file is in the top level directory, then we may receive the URI for the top
    // level, but the actual workspace is the server directory
    return this.currentActiveWorkspace();
  }

  // Displays a quick pick to select which workspace to perform an action on. For example, if multiple workspaces exist,
  // then we need to know which workspace to restart the language server on
  private async showWorkspacePick(): Promise<Workspace | undefined> {
    if (this.workspaces.size === 1) {
      return this.workspaces.values().next().value;
    }

    const workspaceFolder = await vscode.window.showWorkspaceFolderPick();

    if (!workspaceFolder) {
      return;
    }

    return this.getWorkspace(workspaceFolder.uri);
  }

  private async diagnoseState() {
    const workspace = await this.showWorkspacePick();

    const response:
      | {
          workerAlive: boolean;
          backtrace: string[];
          documents: { uri: string; source: string };
          incomingQueueSize: number;
        }
      | null
      | undefined = await workspace?.lspClient?.sendRequest("rubyLsp/diagnoseState");

    if (response) {
      const documentData = Object.entries(response.documents);
      const information = [
        `Worker alive: ${response.workerAlive}`,
        `Incoming queue size: ${response.incomingQueueSize}`,
        `Backtrace:\n${response.backtrace.join("\n")}\n`,
        `=========== Documents (${documentData.length}) ===========`,
        ...documentData.map(([uri, source]) => `URI: ${uri}\n\n${source}\n===========`),
      ].join("\n");

      const document = await vscode.workspace.openTextDocument(
        vscode.Uri.from({
          scheme: "ruby-lsp",
          path: "show-diagnose-state",
          query: information,
        }),
      );

      await vscode.window.showTextDocument(document, {
        viewColumn: vscode.ViewColumn.Beside,
        preserveFocus: true,
      });
    }
  }

  // Show syntax tree command
  private async showSyntaxTree() {
    const activeEditor = vscode.window.activeTextEditor;

    if (activeEditor) {
      const document = activeEditor.document;

      if (document.languageId !== "ruby") {
        await vscode.window.showErrorMessage("Show syntax tree: not a Ruby file");
        return;
      }

      const workspaceFolder = vscode.workspace.getWorkspaceFolder(document.uri);

      if (!workspaceFolder) {
        return;
      }

      const workspace = this.getWorkspace(workspaceFolder.uri);

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

      const response: { ast: string } | null | undefined = await workspace?.lspClient?.sendShowSyntaxTreeRequest(
        document.uri,
        range,
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

  private async showFormatOnSaveModeWarning(workspace: Workspace) {
    const setting = vscode.workspace.getConfiguration("editor", {
      languageId: "ruby",
    });
    const value: string = setting.get("formatOnSaveMode")!;

    if (value === "file") {
      return;
    }

    const answer = await vscode.window.showWarningMessage(
      `The "editor.formatOnSaveMode" setting is set to ${value} in workspace ${workspace.workspaceFolder.name}, which
      is currently unsupported by the Ruby LSP. If you'd like to have formatting enabled, please set it to 'file'`,
      "Change setting to 'file'",
      "Use without formatting",
    );

    if (answer === "Change setting to 'file'") {
      await setting.update("formatOnSaveMode", "file", vscode.ConfigurationTarget.Global);
    }
  }

  private async lockfileExists(workspaceUri: vscode.Uri) {
    try {
      await vscode.workspace.fs.stat(vscode.Uri.joinPath(workspaceUri, "Gemfile.lock"));
      return true;
    } catch (_error: any) {
      // Gemfile.lock doesn't exist, try the next
    }

    try {
      await vscode.workspace.fs.stat(vscode.Uri.joinPath(workspaceUri, "gems.locked"));
      return true;
    } catch (_error: any) {
      // gems.locked doesn't exist
    }

    return false;
  }

  private async showStandaloneWarning(workspaceDir: string) {
    await vscode.window.withProgress(
      {
        location: vscode.ProgressLocation.Notification,
        title: "No bundle found. Launching in standalone mode in 5 seconds",
        cancellable: true,
      },
      async (progress, token) => {
        progress.report({
          message: "If working in a monorepo, cancel to see configuration instructions",
        });

        await new Promise<void>((resolve) => {
          token.onCancellationRequested(() => {
            resolve();
          });

          setTimeout(resolve, 5000);
        });

        if (token.isCancellationRequested) {
          const answer = await vscode.window.showWarningMessage(
            `Could not find a lockfile in ${workspaceDir}. Are you using a monorepo setup?`,
            "See the multi-root workspace docs",
            "Launch anyway",
          );

          if (answer === "See the multi-root workspace docs") {
            const uri = vscode.Uri.parse(
              "https://github.com/Shopify/ruby-lsp/blob/main/vscode/README.md?tab=readme-ov-file#multi-root-workspaces",
            );

            await vscode.env.openExternal(uri);
          }
        }
      },
    );
  }
}
