import * as vscode from "vscode";
import { Range } from "vscode-languageclient/node";

import DocumentProvider from "./documentProvider";
import { Workspace } from "./workspace";
import {
  Command,
  LOG_CHANNEL,
  STATUS_EMITTER,
  SUPPORTED_LANGUAGE_IDS,
} from "./common";
import { ManagerIdentifier, ManagerConfiguration } from "./ruby";
import { StatusItems } from "./status";
import { TestController } from "./testController";
import { newMinitestFile, openFile, openUris } from "./commands";
import { Debugger } from "./debugger";
import { DependenciesTree } from "./dependenciesTree";
import { Rails } from "./rails";
import { ChatAgent } from "./chatAgent";
import { collectRubyLspInfo } from "./infoCollector";

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

  constructor(
    context: vscode.ExtensionContext,
    telemetry: vscode.TelemetryLogger,
  ) {
    this.context = context;
    this.telemetry = telemetry;
    this.testController = new TestController(
      context,
      this.telemetry,
      this.currentActiveWorkspace.bind(this),
    );
    this.debug = new Debugger(context, this.workspaceResolver.bind(this));
    this.rails = new Rails(this.showWorkspacePick.bind(this));
    this.registerCommands(context);

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

        const workspaceFolder = vscode.workspace.getWorkspaceFolder(
          document.uri,
        );

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

    if (
      activeDocument &&
      SUPPORTED_LANGUAGE_IDS.includes(activeDocument.languageId)
    ) {
      const workspaceFolder = vscode.workspace.getWorkspaceFolder(
        activeDocument.uri,
      );

      if (workspaceFolder && workspaceFolder !== firstWorkspace) {
        await this.activateWorkspace(workspaceFolder, true);
      }
    }

    this.context.subscriptions.push(
      vscode.workspace.registerTextDocumentContentProvider(
        "ruby-lsp",
        new DocumentProvider(),
      ),
    );

    STATUS_EMITTER.fire(this.currentActiveWorkspace());
  }

  // Deactivate the extension, which should stop all language servers. Notice that this just stops anything that is
  // running, but doesn't dispose of existing instances
  async deactivate() {
    for (const workspace of this.workspaces.values()) {
      await workspace.stop();
    }
  }

  private async activateWorkspace(
    workspaceFolder: vscode.WorkspaceFolder,
    eager: boolean,
  ) {
    const workspaceDir = workspaceFolder.uri.fsPath;
    const customBundleGemfile: string = vscode.workspace
      .getConfiguration("rubyLsp")
      .get("bundleGemfile")!;

    const lockfileExists = await this.lockfileExists(workspaceFolder.uri);

    // When eagerly activating workspaces, we skip the ones that do not have a lockfile since they may not be a Ruby
    // workspace. Those cases are activated lazily below
    if (eager && !lockfileExists) {
      return;
    }

    // If no lockfile exists and we're activating lazily (if the user opened a Ruby file inside a workspace we hadn't
    // activated before), then we start the language server, but we warn the user that they may be missing multi-root
    // workspace configuration
    if (
      customBundleGemfile.length === 0 &&
      !lockfileExists &&
      !this.context.globalState.get("rubyLsp.disableMultirootLockfileWarning")
    ) {
      const answer = await vscode.window.showWarningMessage(
        `Activating the Ruby LSP in ${workspaceDir}, but no lockfile was found. Are you using a monorepo setup?`,
        "See the multi-root workspace docs",
        "Don't show again",
      );

      if (answer === "See the multi-root workspace docs") {
        await vscode.env.openExternal(
          vscode.Uri.parse(
            "https://github.com/Shopify/ruby-lsp/blob/main/vscode/README.md?tab=readme-ov-file#multi-root-workspaces",
          ),
        );
      }

      if (answer === "Don't show again") {
        await this.context.globalState.update(
          "rubyLsp.disableMultirootLockfileWarning",
          true,
        );
      }
    }

    const workspace = new Workspace(
      this.context,
      workspaceFolder,
      this.telemetry,
      this.testController.createTestItems.bind(this.testController),
      this.virtualDocuments,
      this.workspaces.size === 0,
    );
    this.workspaces.set(workspaceFolder.uri.toString(), workspace);

    await workspace.start();
    this.context.subscriptions.push(workspace);

    // If we successfully activated a workspace, then we can start showing the dependencies tree view. This is necessary
    // so that we can avoid showing it on non Ruby projects
    await vscode.commands.executeCommand(
      "setContext",
      "rubyLsp.activated",
      true,
    );
    await this.showFormatOnSaveModeWarning(workspace);
  }

  // Registers all extension commands. Commands can only be registered once, so this happens in the constructor. For
  // creating multiple instances in tests, the `RubyLsp` object should be disposed of after each test to prevent double
  // command register errors
  private registerCommands(context: vscode.ExtensionContext) {
    context.subscriptions.push(
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
        await workspace?.stop();
      }),
      vscode.commands.registerCommand(
        Command.ShowSyntaxTree,
        this.showSyntaxTree.bind(this),
      ),
      vscode.commands.registerCommand(Command.FormatterHelp, () => {
        return vscode.env.openExternal(
          vscode.Uri.parse(
            "https://github.com/Shopify/ruby-lsp/blob/main/vscode/README.md#formatting",
          ),
        );
      }),
      vscode.commands.registerCommand(Command.DisplayAddons, async () => {
        const client = this.currentActiveWorkspace()?.lspClient;

        if (!client || !client.addons) {
          return;
        }

        const options: vscode.QuickPickItem[] = client.addons
          .sort((addon) => {
            // Display errored addons last
            if (addon.errored) {
              return 1;
            }

            return -1;
          })
          .map((addon) => {
            const icon = addon.errored ? "$(error)" : "$(pass)";
            return {
              label: `${icon} ${addon.name}`,
            };
          });

        await vscode.window.showQuickPick(options, {
          placeHolder: "Addons (readonly)",
        });
      }),
      vscode.commands.registerCommand(Command.ToggleFeatures, async () => {
        // Extract feature descriptions from our package.json
        const enabledFeaturesProperties =
          vscode.extensions.getExtension("Shopify.ruby-lsp")!.packageJSON
            .contributes.configuration.properties["rubyLsp.enabledFeatures"]
            .properties;

        const descriptions: Record<string, string> = {};
        Object.entries(enabledFeaturesProperties).forEach(
          ([key, value]: [string, any]) => {
            descriptions[key] = value.description;
          },
        );

        const configuration = vscode.workspace.getConfiguration("rubyLsp");
        const features: Record<string, boolean> =
          configuration.get("enabledFeatures")!;
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
            features[feature] = toggledFeatures.some(
              (selected) => selected.label === feature,
            );
          });

          await vscode.workspace
            .getConfiguration("rubyLsp")
            .update("enabledFeatures", features, true, true);
        }
      }),
      vscode.commands.registerCommand(
        Command.ToggleExperimentalFeatures,
        async () => {
          const lspConfig = vscode.workspace.getConfiguration("rubyLsp");
          const experimentalFeaturesEnabled = lspConfig.get(
            "enableExperimentalFeatures",
          );
          await lspConfig.update(
            "enableExperimentalFeatures",
            !experimentalFeaturesEnabled,
            true,
            true,
          );

          STATUS_EMITTER.fire(this.currentActiveWorkspace());
        },
      ),
      vscode.commands.registerCommand(
        Command.ServerOptions,
        async (options: [{ label: string; description: string }]) => {
          const result = await vscode.window.showQuickPick(options, {
            placeHolder: "Select server action",
          });

          if (result !== undefined)
            await vscode.commands.executeCommand(result.description);
        },
      ),
      vscode.commands.registerCommand(
        Command.SelectVersionManager,
        async () => {
          const answer = await vscode.window.showQuickPick(
            ["Change version manager", "Change manual Ruby configuration"],
            { placeHolder: "What would you like to do?" },
          );

          if (!answer) {
            return;
          }

          if (answer === "Change version manager") {
            const configuration = vscode.workspace.getConfiguration("rubyLsp");
            const managerConfig =
              configuration.get<ManagerConfiguration>("rubyVersionManager")!;
            const options = Object.values(ManagerIdentifier);
            const manager = (await vscode.window.showQuickPick(options, {
              placeHolder: `Current: ${managerConfig.identifier}`,
            })) as ManagerIdentifier | undefined;

            if (manager !== undefined) {
              managerConfig.identifier = manager;
              await configuration.update(
                "rubyVersionManager",
                managerConfig,
                true,
              );
            }

            return;
          }

          const workspace = await this.showWorkspacePick();

          if (!workspace) {
            return;
          }

          await workspace.ruby.manuallySelectRuby();
        },
      ),
      vscode.commands.registerCommand(
        Command.RunTest,
        (_path, name, _command) => {
          return this.testController.runOnClick(name);
        },
      ),
      vscode.commands.registerCommand(
        Command.RunTestInTerminal,
        this.testController.runTestInTerminal.bind(this.testController),
      ),
      vscode.commands.registerCommand(
        Command.DebugTest,
        this.testController.debugTest.bind(this.testController),
      ),
      vscode.commands.registerCommand(
        Command.RunTask,
        async (command: string) => {
          let workspace = this.currentActiveWorkspace();

          if (!workspace) {
            workspace = await this.showWorkspacePick();
          }

          if (!workspace) {
            return;
          }

          await workspace.execute(command, true);
        },
      ),
      vscode.commands.registerCommand(
        Command.BundleInstall,
        (workspaceUri: string) => {
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
        },
      ),
      vscode.commands.registerCommand(
        Command.OpenFile,
        (rubySourceLocation: [string, string] | string[]) => {
          // New command format: accepts an array of URIs
          if (typeof rubySourceLocation[0] === "string") {
            return openUris(rubySourceLocation);
          }

          // Old format: we can remove after the Rails addon has been using the new format for a while
          const [file, line] = rubySourceLocation;
          const workspace = this.currentActiveWorkspace();
          return openFile(this.telemetry, workspace, {
            file,
            line: parseInt(line, 10) - 1,
          });
        },
      ),
      vscode.commands.registerCommand(
        Command.RailsGenerate,
        async (
          generatorWithArguments: string | string[] | undefined,
          workspace: Workspace | undefined,
        ) => {
          // If the command was invoked programmatically, then the arguments will already be present. Otherwise, we need
          // to show a UI so that the user can pick the arguments to generate
          const command =
            generatorWithArguments ??
            (await vscode.window.showInputBox({
              title: "Rails generate arguments",
              placeHolder:
                "model User name:string | scaffold Post title:string",
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
        async (
          generatorWithArguments: string | string[] | undefined,
          workspace: Workspace | undefined,
        ) => {
          // If the command was invoked programmatically, then the arguments will already be present. Otherwise, we need
          // to show a UI so that the user can pick the arguments to destroy
          const command =
            generatorWithArguments ??
            (await vscode.window.showInputBox({
              title: "Rails destroy arguments",
              placeHolder:
                "model User name:string | scaffold Post title:string",
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

        if (
          workspace.lspClient?.addons?.some(
            (addon) => addon.name === "Ruby LSP Rails",
          )
        ) {
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
      vscode.commands.registerCommand(
        Command.StartServerInDebugMode,
        async () => {
          const workspace = await this.showWorkspacePick();
          await workspace?.start(true);
        },
      ),
    );
  }

  // Get the current active workspace based on which file is opened in the editor
  private currentActiveWorkspace(
    activeEditor = vscode.window.activeTextEditor,
  ): Workspace | undefined {
    let workspaceFolder: vscode.WorkspaceFolder | undefined;

    if (activeEditor) {
      workspaceFolder = vscode.workspace.getWorkspaceFolder(
        activeEditor.document.uri,
      );
    } else {
      // If there's no active editor, we search based on the current workspace name
      workspaceFolder = vscode.workspace.workspaceFolders?.find(
        (folder) => folder.name === vscode.workspace.name,
      );
    }

    if (!workspaceFolder) {
      return;
    }

    return this.getWorkspace(workspaceFolder.uri);
  }

  private getWorkspace(uri: vscode.Uri): Workspace | undefined {
    return this.workspaces.get(uri.toString());
  }

  private workspaceResolver(
    uri: vscode.Uri | undefined,
  ): Workspace | undefined {
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

  // Show syntax tree command
  private async showSyntaxTree() {
    const activeEditor = vscode.window.activeTextEditor;

    if (activeEditor) {
      const document = activeEditor.document;

      if (document.languageId !== "ruby") {
        await vscode.window.showErrorMessage(
          "Show syntax tree: not a Ruby file",
        );
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

      const response: { ast: string } | null | undefined =
        await workspace?.lspClient?.sendShowSyntaxTreeRequest(
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
      await setting.update(
        "formatOnSaveMode",
        "file",
        vscode.ConfigurationTarget.Global,
      );
    }
  }

  private async lockfileExists(workspaceUri: vscode.Uri) {
    try {
      await vscode.workspace.fs.stat(
        vscode.Uri.joinPath(workspaceUri, "Gemfile.lock"),
      );
      return true;
    } catch (error: any) {
      // Gemfile.lock doesn't exist, try the next
    }

    try {
      await vscode.workspace.fs.stat(
        vscode.Uri.joinPath(workspaceUri, "gems.locked"),
      );
      return true;
    } catch (error: any) {
      // gems.locked doesn't exist
    }

    return false;
  }
}
