import { exec, spawn } from "child_process";
import { promisify } from "util";
import path from "path";

import * as rpc from "vscode-jsonrpc/node";
import * as vscode from "vscode";
import { CodeLens } from "vscode-languageclient/node";

import { Workspace } from "./workspace";
import { featureEnabled } from "./common";
import { LspTestItem, ServerTestItem } from "./client";

const asyncExec = promisify(exec);

interface CodeLensData {
  type: string;
  // eslint-disable-next-line @typescript-eslint/naming-convention
  group_id: number;
  id?: number;
  kind: string;
}

const WORKSPACE_TAG = new vscode.TestTag("workspace");
const TEST_DIR_TAG = new vscode.TestTag("test_dir");
const TEST_GROUP_TAG = new vscode.TestTag("test_group");
const DEBUG_TAG = new vscode.TestTag("debug");
const TEST_FILE_TAG = new vscode.TestTag("test_file");

interface TestEventId {
  uri: string;
  id: string;
}
type TestEventWithMessage = TestEventId & { message: string };

// All notification types that may be produce by our custom JSON test reporter
const NOTIFICATION_TYPES = {
  start: new rpc.NotificationType<TestEventId>("start"),
  pass: new rpc.NotificationType<TestEventId>("pass"),
  skip: new rpc.NotificationType<TestEventId>("skip"),
  fail: new rpc.NotificationType<TestEventWithMessage>("fail"),
  error: new rpc.NotificationType<TestEventWithMessage>("error"),
  appendOutput: new rpc.NotificationType<{ message: string }>("append_output"),
};

export class TestController {
  // Only public for testing
  readonly testController: vscode.TestController;
  private readonly testCommands: WeakMap<vscode.TestItem, string>;
  private readonly testRunProfile: vscode.TestRunProfile;
  private readonly testDebugProfile: vscode.TestRunProfile;
  private terminal: vscode.Terminal | undefined;
  private readonly telemetry: vscode.TelemetryLogger;
  // We allow the timeout to be configured in seconds, but exec expects it in milliseconds
  private readonly testTimeout = vscode.workspace
    .getConfiguration("rubyLsp")
    .get("testTimeout") as number;

  private readonly currentWorkspace: () => Workspace | undefined;
  private readonly getOrActivateWorkspace: (
    workspaceFolder: vscode.WorkspaceFolder,
  ) => Promise<Workspace>;

  private readonly fullDiscovery = featureEnabled("fullTestDiscovery");

  constructor(
    context: vscode.ExtensionContext,
    telemetry: vscode.TelemetryLogger,
    currentWorkspace: () => Workspace | undefined,
    getOrActivateWorkspace: (
      workspaceFolder: vscode.WorkspaceFolder,
    ) => Promise<Workspace>,
  ) {
    this.telemetry = telemetry;
    this.currentWorkspace = currentWorkspace;
    this.getOrActivateWorkspace = getOrActivateWorkspace;
    this.testController = vscode.tests.createTestController(
      "rubyTests",
      "Ruby Tests",
    );

    if (this.fullDiscovery) {
      this.testController.resolveHandler = this.resolveHandler.bind(this);
    }

    this.testCommands = new WeakMap<vscode.TestItem, string>();

    this.testRunProfile = this.testController.createRunProfile(
      "Run",
      vscode.TestRunProfileKind.Run,
      this.fullDiscovery ? this.runTest.bind(this) : this.runHandler.bind(this),
      true,
    );

    this.testDebugProfile = this.testController.createRunProfile(
      "Debug",
      vscode.TestRunProfileKind.Debug,
      async (request, token) => {
        await this.debugHandler(request, token);
      },
      false,
      DEBUG_TAG,
    );

    const testFileWatcher = vscode.workspace.createFileSystemWatcher(
      "**/{test,spec,features}/**/{*_test.rb,test_*.rb,*_spec.rb,*.feature}",
    );

    context.subscriptions.push(
      this.testController,
      this.testDebugProfile,
      this.testRunProfile,
      vscode.window.onDidCloseTerminal((terminal: vscode.Terminal): void => {
        if (terminal === this.terminal) this.terminal = undefined;
      }),
      testFileWatcher,
      testFileWatcher.onDidChange(async (uri) => {
        const item = await this.getParentTestItem(uri);

        if (item) {
          const testFile = item.children.get(uri.toString());

          if (testFile) {
            testFile.children.replace([]);
            await this.resolveHandler(testFile);
          }
        }
      }),
      testFileWatcher.onDidDelete(async (uri) => {
        const item = await this.getParentTestItem(uri);

        if (item) {
          item.children.delete(uri.toString());
        }
      }),
    );
  }

  createTestItems(response: CodeLens[]) {
    // In the new experience, we will no longer overload code lens
    if (this.fullDiscovery) {
      return;
    }

    this.testController.items.forEach((test) => {
      this.testController.items.delete(test.id);
      this.testCommands.delete(test);
    });

    const groupIdMap: Map<number, vscode.TestItem> = new Map();

    const uri = vscode.Uri.from({
      scheme: "file",
      path: response[0].command!.arguments![0],
    });

    response.forEach((res) => {
      const [_, name, command, location, label] = res.command!.arguments!;
      const testItem: vscode.TestItem = this.testController.createTestItem(
        name,
        label || name,
        uri,
      );

      const data: CodeLensData = res.data;

      testItem.tags = [new vscode.TestTag(data.kind)];

      this.testCommands.set(testItem, command);

      testItem.range = new vscode.Range(
        new vscode.Position(location.start_line, location.start_column),
        new vscode.Position(location.end_line, location.end_column),
      );

      // If it has an id, it's a group. Otherwise, it's a test example
      if (data.id) {
        // Add group to the map
        groupIdMap.set(data.id, testItem);
        testItem.canResolveChildren = true;
      } else {
        // Set example tags
        testItem.tags = [...testItem.tags, DEBUG_TAG];
      }

      // Examples always have a `group_id`. Groups may or may not have it
      if (data.group_id) {
        // Add nested group to its parent group
        const group = groupIdMap.get(data.group_id);

        // If there's a mistake on the server or in an add-on, a code lens may be produced for a non-existing group
        if (group) {
          group.children.add(testItem);
        } else {
          this.currentWorkspace()?.outputChannel.error(
            `Test example "${name}" is attached to group_id ${data.group_id}, but that group does not exist`,
          );
        }
      } else {
        // Or add it to the top-level
        this.testController.items.add(testItem);
      }
    });
  }

  runTestInTerminal(_path: string, _name: string, command?: string) {
    // eslint-disable-next-line no-param-reassign
    command ??= this.testCommands.get(this.findTestByActiveLine()!) || "";

    if (this.terminal === undefined) {
      this.terminal = this.getTerminal();
    }

    this.terminal.show();
    this.terminal.sendText(command);

    this.telemetry.logUsage("ruby_lsp.code_lens", {
      type: "counter",
      attributes: {
        label: "test_in_terminal",
        vscodemachineid: vscode.env.machineId,
      },
    });
  }

  async runOnClick(testId: string) {
    const test = this.findTestById(testId);

    if (!test) return;

    await vscode.commands.executeCommand("vscode.revealTestInExplorer", test);
    let tokenSource: vscode.CancellationTokenSource | null =
      new vscode.CancellationTokenSource();

    tokenSource.token.onCancellationRequested(async () => {
      tokenSource?.dispose();
      tokenSource = null;

      await vscode.window.showInformationMessage("Cancelled the progress");
    });

    const testRun = new vscode.TestRunRequest([test], [], this.testRunProfile);
    return this.testRunProfile.runHandler(testRun, tokenSource.token);
  }

  debugTest(_path: string, _name: string, command?: string) {
    // eslint-disable-next-line no-param-reassign
    command ??= this.testCommands.get(this.findTestByActiveLine()!) || "";

    const workspace = this.currentWorkspace();

    if (!workspace) {
      throw new Error(
        "No workspace found. Debugging requires a workspace to be opened",
      );
    }

    return vscode.debug.startDebugging(workspace.workspaceFolder, {
      type: "ruby_lsp",
      name: "Debug",
      request: "launch",
      program: command,
      env: { ...workspace.ruby.env, DISABLE_SPRING: "1" },
    });
  }

  // Public for testing purposes. Receives the controller's inclusions and exclusions and builds request test items for
  // the server to resolve the command
  buildRequestTestItems(
    inclusions: vscode.TestItem[],
    exclusions: ReadonlyArray<vscode.TestItem> | undefined,
  ): LspTestItem[] {
    if (!exclusions) {
      return inclusions.map((item) => this.testItemToServerItem(item));
    }

    const filtered: LspTestItem[] = [];

    inclusions.forEach((item) => {
      const includedItem = this.recursivelyFilter(item, exclusions);

      if (includedItem) {
        filtered.push(includedItem);
      }
    });

    return filtered;
  }

  async runTest(
    request: vscode.TestRunRequest,
    token: vscode.CancellationToken,
  ) {
    const run = this.testController.createTestRun(request, undefined, true);

    // Gather all included test items
    const items: vscode.TestItem[] = [];
    if (request.include) {
      request.include.forEach((test) => items.push(test));
    } else {
      this.testController.items.forEach((test) => items.push(test));
    }

    const workspaceToTestItems = new Map<
      vscode.WorkspaceFolder,
      vscode.TestItem[]
    >();

    // Organize the tests based on their workspace folder. Each workspace has their own LSP server running and may be
    // using a different test framework, so we need to use the workspace associated with each item
    items.forEach((item) => {
      const workspaceFolder = vscode.workspace.getWorkspaceFolder(item.uri!)!;
      const existingEntry = workspaceToTestItems.get(workspaceFolder);

      if (existingEntry) {
        existingEntry.push(item);
      } else {
        workspaceToTestItems.set(workspaceFolder, [item]);
      }
    });

    for (const [workspaceFolder, testItems] of workspaceToTestItems) {
      if (token.isCancellationRequested) {
        break;
      }

      // Build the test item parameters that we send to the server, filtering out exclusions. Then ask the server for
      // the resolved test commands
      const requestTestItems = this.buildRequestTestItems(
        testItems,
        request.exclude,
      );
      const workspace = await this.getOrActivateWorkspace(workspaceFolder);
      const response =
        await workspace.lspClient?.resolveTestCommands(requestTestItems);

      if (!response) {
        testItems.forEach((test) =>
          run.errored(
            test,
            new vscode.TestMessage(
              "Could not resolve test command to run selected tests",
            ),
          ),
        );
        continue;
      }

      // Enqueue all of the test we're about to run
      testItems.forEach((test) => run.enqueued(test));

      // Require the custom JSON RPC reporters through RUBYOPT. We cannot use Ruby's `-r` flag because the moment the
      // test framework is loaded, it might change which options are accepted. For example, if we append `-r` after the
      // file path for Minitest, it will fail with unrecognized argument errors
      const rubyOpt = workspace.ruby.env.RUBYOPT
        ? `${workspace.ruby.env.RUBYOPT} ${response.reporterPaths?.map((path) => `-r${path}`).join(" ")}`
        : response.reporterPaths?.map((path) => `-r${path}`).join(" ");

      // For each command reported by the server spawn a new process with streaming updates
      for (const command of response.commands) {
        try {
          workspace.outputChannel.debug(
            `Running tests: "RUBYOPT=${rubyOpt} ${command}"`,
          );
          await this.runCommandWithStreamingUpdates(
            run,
            command,
            {
              ...workspace.ruby.env,
              RUBY_LSP_TEST_RUNNER: "true",
              RUBYOPT: rubyOpt,
            },
            workspace.workspaceFolder.uri.fsPath,
            token,
          );
        } catch (error: any) {
          await vscode.window.showErrorMessage(
            `Running ${command} failed: ${error.message}`,
          );
        }
      }
    }

    run.end();
  }

  // Public for testing purposes. Finds a test item based on its ID and URI
  async findTestItem(id: string, uri: vscode.Uri) {
    const parentItem = await this.getParentTestItem(uri);
    if (!parentItem) {
      return;
    }

    if (parentItem.id === id) {
      return parentItem;
    }

    const testFileItem = parentItem.children.get(uri.toString());
    if (!testFileItem) {
      return;
    }

    if (testFileItem.id === id) {
      return testFileItem;
    }

    // If we're trying to find a test item inside a file that has never been expanded, then we never discovered its
    // children and need to do so before trying to access them
    if (testFileItem.children.size === 0) {
      await this.resolveHandler(testFileItem);
    }

    // If we find an exact match for this ID, then return it right away
    const groupOrItem = testFileItem.children.get(id);
    if (groupOrItem) {
      return groupOrItem;
    }

    // If not, the ID might be nested under groups
    return this.findTestInGroup(id, testFileItem);
  }

  private findTestInGroup(
    id: string,
    group: vscode.TestItem,
  ): vscode.TestItem | undefined {
    let found: vscode.TestItem | undefined;

    group.children.forEach((item) => {
      if (id.startsWith(`${item.id}#`) || id.startsWith(`${item.id}::`)) {
        found = item;
      }
    });

    if (!found) {
      return;
    }

    return found.children.get(id) ?? this.findTestInGroup(id, found);
  }

  // Get an existing terminal or create a new one. For multiple workspaces, it's important to create a new terminal for
  // each workspace because they might be using different Ruby versions. If there's no workspace, we fallback to a
  // generic name
  private getTerminal() {
    const workspace = this.currentWorkspace();
    const name = workspace
      ? `${workspace.workspaceFolder.name}: test`
      : "Ruby LSP: test";

    const previousTerminal = vscode.window.terminals.find(
      (terminal) => terminal.name === name,
    );

    return previousTerminal
      ? previousTerminal
      : vscode.window.createTerminal({
          name,
        });
  }

  private async debugHandler(
    request: vscode.TestRunRequest,
    _token: vscode.CancellationToken,
  ) {
    const run = this.testController.createTestRun(request, undefined, true);
    const test = request.include![0];

    const start = Date.now();
    await this.debugTest("", "", this.testCommands.get(test)!);
    run.passed(test, Date.now() - start);
    run.end();

    this.telemetry.logUsage("ruby_lsp.code_lens", {
      type: "counter",
      attributes: { label: "debug", vscodemachineid: vscode.env.machineId },
    });
  }

  private async runHandler(
    request: vscode.TestRunRequest,
    token: vscode.CancellationToken,
  ) {
    const run = this.testController.createTestRun(request, undefined, true);
    const queue: vscode.TestItem[] = [];
    const enqueue = (test: vscode.TestItem) => {
      queue.push(test);
      run.enqueued(test);
    };

    if (request.include) {
      request.include.forEach(enqueue);
    } else {
      this.testController.items.forEach(enqueue);
    }
    const workspace = this.currentWorkspace();

    while (queue.length > 0 && !token.isCancellationRequested) {
      const test = queue.pop()!;

      if (request.exclude?.includes(test)) {
        run.skipped(test);
        continue;
      }
      run.started(test);

      if (test.tags.find((tag) => tag.id === "example")) {
        const start = Date.now();
        try {
          if (!workspace) {
            run.errored(test, new vscode.TestMessage("No workspace found"));
            continue;
          }

          const output: string = await this.assertTestPasses(
            test,
            workspace.workspaceFolder.uri.fsPath,
            workspace.ruby.env,
          );

          run.appendOutput(output.replace(/\r?\n/g, "\r\n"), undefined, test);
          run.passed(test, Date.now() - start);
        } catch (err: any) {
          run.appendOutput(
            err.message.replace(/\r?\n/g, "\r\n"),
            undefined,
            test,
          );

          const duration = Date.now() - start;

          if (err.killed) {
            run.errored(
              test,
              new vscode.TestMessage(
                `Test timed out after ${this.testTimeout} seconds`,
              ),
              duration,
            );
            continue;
          }

          const messageArr = err.message.split("\n");

          // Minitest and test/unit outputs are formatted differently so we need to slice the message
          // differently to get an output format that only contains essential information
          // If the first element of the message array is "", we know the output is a Minitest output
          const summary =
            messageArr[0] === ""
              ? messageArr.slice(10, messageArr.length - 2).join("\n")
              : messageArr.slice(4, messageArr.length - 9).join("\n");

          const messages = [
            new vscode.TestMessage(err.message),
            new vscode.TestMessage(summary),
          ];

          if (messageArr.find((elem: string) => elem === "F")) {
            run.failed(test, messages, duration);
          } else {
            run.errored(test, messages, duration);
          }
        }
      }

      test.children.forEach(enqueue);
    }

    // Make sure to end the run after all tests have been executed
    run.end();

    this.telemetry.logUsage("ruby_lsp.code_lens", {
      type: "counter",
      attributes: { label: "test", vscodemachineid: vscode.env.machineId },
    });
  }

  private async assertTestPasses(
    test: vscode.TestItem,
    cwd: string,
    env: NodeJS.ProcessEnv,
  ) {
    try {
      const result = await asyncExec(this.testCommands.get(test)!, {
        cwd,
        env,
        timeout: this.testTimeout * 1000,
      });
      return result.stdout;
    } catch (error: any) {
      if (error.killed) {
        throw error;
      } else {
        throw new Error(error.stdout);
      }
    }
  }

  private findTestById(
    testId: string,
    testItems: vscode.TestItemCollection = this.testController.items,
  ) {
    if (!testId) {
      return this.findTestByActiveLine();
    }

    let testItem = testItems.get(testId);

    if (testItem) return testItem;

    testItems.forEach((test) => {
      const childTestItem = this.findTestById(testId, test.children);
      if (childTestItem) testItem = childTestItem;
    });

    return testItem;
  }

  private findTestByActiveLine(
    editor: vscode.TextEditor | undefined = vscode.window.activeTextEditor,
    testItems: vscode.TestItemCollection = this.testController.items,
  ): vscode.TestItem | undefined {
    if (!editor) {
      return;
    }

    const line = editor.selection.active.line;
    let testItem: vscode.TestItem | undefined;

    testItems.forEach((test) => {
      if (testItem) return;

      if (
        test.uri?.toString() === editor.document.uri.toString() &&
        test.range?.start.line! <= line &&
        test.range?.end.line! >= line
      ) {
        testItem = test;
      }

      if (test.children.size > 0) {
        const childInRange = this.findTestByActiveLine(editor, test.children);
        if (childInRange) {
          testItem = childInRange;
        }
      }
    });

    return testItem;
  }

  private async resolveHandler(
    item: vscode.TestItem | undefined,
  ): Promise<void> {
    const workspaceFolders = vscode.workspace.workspaceFolders;
    if (!workspaceFolders) {
      return;
    }

    if (item) {
      const workspaceFolder = vscode.workspace.getWorkspaceFolder(item.uri!)!;

      // If the item is a workspace, then we need to gather all test files inside of it
      if (item.tags.some((tag) => tag === WORKSPACE_TAG)) {
        await this.gatherWorkspaceTests(workspaceFolder, item);
      } else if (!item.tags.some((tag) => tag === TEST_GROUP_TAG)) {
        const workspace = await this.getOrActivateWorkspace(workspaceFolder);
        const lspClient = workspace.lspClient;

        if (lspClient) {
          await lspClient.waitForIndexing();
          const testItems = await lspClient.discoverTests(item.uri!);

          if (testItems) {
            this.addDiscoveredItems(testItems, item);
          }
        }
      }
    } else if (workspaceFolders.length === 1) {
      // If there's only one workspace, there's no point in nesting the tests under the workspace name
      await vscode.commands.executeCommand("testing.clearTestResults");
      await this.gatherWorkspaceTests(workspaceFolders[0], undefined);
    } else {
      // If there's more than one workspace, we use them as the top level items
      await vscode.commands.executeCommand("testing.clearTestResults");
      for (const workspaceFolder of workspaceFolders) {
        // Check if there is at least one Ruby test file in the workspace, otherwise we don't consider it
        const pattern = this.testPattern(workspaceFolder);
        const files = await vscode.workspace.findFiles(pattern, undefined, 1);
        if (files.length === 0) {
          continue;
        }

        const uri = workspaceFolder.uri;
        const testItem = this.testController.createTestItem(
          uri.toString(),
          workspaceFolder.name,
          uri,
        );
        testItem.canResolveChildren = true;
        testItem.tags = [WORKSPACE_TAG, DEBUG_TAG];
        this.testController.items.add(testItem);
      }
    }
  }

  private async gatherWorkspaceTests(
    workspaceFolder: vscode.WorkspaceFolder,
    item: vscode.TestItem | undefined,
  ) {
    const initialCollection = item ? item.children : this.testController.items;
    const pattern = this.testPattern(workspaceFolder);

    for (const uri of await vscode.workspace.findFiles(pattern)) {
      const fileName = path.basename(uri.fsPath);
      const relativePath = vscode.workspace.asRelativePath(uri, false);
      const pathParts = relativePath.split(path.sep);

      if (this.shouldSkipTestFile(fileName, pathParts)) {
        continue;
      }

      // Find the position of the `test/spec/feature` directory. There may be many in applications that are divided by
      // components, so we want to show each individual test directory as a separate item
      const dirPosition = this.testDirectoryPosition(pathParts);

      // Get or create the first level test directory item
      const { firstLevel, firstLevelUri } = this.getOrCreateFirstLevelItem(
        pathParts,
        dirPosition,
        workspaceFolder,
        initialCollection,
      );

      // Get or create the second level test directory item if applicable
      const finalCollection = await this.getOrCreateSecondLevelItem(
        pathParts,
        dirPosition,
        firstLevelUri,
        firstLevel,
      );

      // Add the test file to the appropriate collection
      this.addTestFileItem(uri, fileName, finalCollection);
    }
  }

  private addTestFileItem(
    uri: vscode.Uri,
    fileName: string,
    collection: vscode.TestItemCollection,
  ) {
    // Finally, add the test file to whatever is the final collection, which may be the first level test directory or
    // a second level like models
    const testItem = this.testController.createTestItem(
      uri.toString(),
      fileName,
      uri,
    );
    testItem.canResolveChildren = true;
    testItem.tags = [TEST_FILE_TAG, DEBUG_TAG];
    collection.add(testItem);
  }

  private getOrCreateFirstLevelItem(
    pathParts: string[],
    dirPosition: number,
    workspaceFolder: vscode.WorkspaceFolder,
    initialCollection: vscode.TestItemCollection,
  ): { firstLevel: vscode.TestItem; firstLevelUri: vscode.Uri } {
    const firstLevelName = pathParts.slice(0, dirPosition + 1).join(path.sep);
    const firstLevelUri = vscode.Uri.joinPath(
      workspaceFolder.uri,
      firstLevelName,
    );

    let firstLevel = initialCollection.get(firstLevelUri.toString());
    if (!firstLevel) {
      firstLevel = this.testController.createTestItem(
        firstLevelUri.toString(),
        firstLevelName,
        firstLevelUri,
      );
      firstLevel.tags = [TEST_DIR_TAG, DEBUG_TAG];
      initialCollection.add(firstLevel);
    }

    return { firstLevel, firstLevelUri };
  }

  private async getOrCreateSecondLevelItem(
    pathParts: string[],
    dirPosition: number,
    firstLevelUri: vscode.Uri,
    firstLevel: vscode.TestItem,
  ): Promise<vscode.TestItemCollection> {
    // In Rails apps, it's also very common to divide the test directory into a second hierarchy level, like models or
    // controllers. Here we try to find out if there is a second level, allowing users to run all tests for models for
    // example
    const secondLevelName = pathParts
      .slice(dirPosition + 1, dirPosition + 2)
      .join(path.sep);
    const secondLevelUri = vscode.Uri.joinPath(firstLevelUri, secondLevelName);

    try {
      const fileStat = await vscode.workspace.fs.stat(secondLevelUri);

      // We only consider something to be another level of hierarchy if it's a directory
      if (fileStat.type === vscode.FileType.Directory) {
        let secondLevel = firstLevel.children.get(secondLevelUri.toString());

        if (!secondLevel) {
          secondLevel = this.testController.createTestItem(
            secondLevelUri.toString(),
            secondLevelName,
            secondLevelUri,
          );
          secondLevel.tags = [TEST_DIR_TAG, DEBUG_TAG];
          firstLevel.children.add(secondLevel);
        }

        return secondLevel.children;
      }
    } catch (error: any) {
      // Do nothing
    }

    return firstLevel.children;
  }

  private shouldSkipTestFile(fileName: string, pathParts: string[]) {
    if (fileName === "test_helper.rb") {
      return true;
    }

    // Projects may have fixtures that are test files, but not real tests to be executed. We don't want to include
    // those
    if (pathParts.some((part) => part === "fixtures")) {
      return true;
    }

    return false;
  }

  private testPattern(workspaceFolder: vscode.WorkspaceFolder) {
    return new vscode.RelativePattern(
      workspaceFolder,
      "**/{test,spec,features}/**/{*_test.rb,test_*.rb,*_spec.rb,*.feature}",
    );
  }

  private testDirectoryPosition(pathParts: string[]) {
    let index = pathParts.indexOf("test");
    if (index !== -1) {
      return index;
    }

    index = pathParts.indexOf("spec");
    if (index !== -1) {
      return index;
    }

    return pathParts.indexOf("features");
  }

  private async getParentTestItem(uri: vscode.Uri) {
    const workspaceFolders = vscode.workspace.workspaceFolders;
    if (!workspaceFolders) {
      return undefined;
    }

    let initialCollection = this.testController.items;
    let workspaceFolder = workspaceFolders[0];

    // If there's more than one workspace folder, then the first level is the workspace
    if (workspaceFolders.length > 1) {
      workspaceFolder = vscode.workspace.getWorkspaceFolder(uri)!;

      initialCollection = initialCollection.get(
        workspaceFolder.uri.toString(),
      )!.children;
    }

    // There's always a first level, but not always a second level
    const { firstLevelUri, secondLevelUri } = await this.directoryLevelUris(
      uri,
      workspaceFolder,
    );

    let item = initialCollection.get(firstLevelUri.toString());

    if (secondLevelUri) {
      item = item?.children.get(secondLevelUri.toString());
    }

    return item;
  }

  private async directoryLevelUris(
    uri: vscode.Uri,
    workspaceFolder: vscode.WorkspaceFolder,
  ): Promise<{
    firstLevelUri: vscode.Uri;
    secondLevelUri: vscode.Uri | undefined;
  }> {
    const relativePath = vscode.workspace.asRelativePath(uri, false);
    const pathParts = relativePath.split(path.sep);
    const dirPosition = this.testDirectoryPosition(pathParts);
    const firstLevelName = pathParts.slice(0, dirPosition + 1).join(path.sep);
    const firstLevelUri = vscode.Uri.joinPath(
      workspaceFolder.uri,
      firstLevelName,
    );

    const secondLevelName = pathParts
      .slice(dirPosition + 1, dirPosition + 2)
      .join(path.sep);

    if (secondLevelName.length > 0) {
      const secondLevelUri = vscode.Uri.joinPath(
        firstLevelUri,
        secondLevelName,
      );

      try {
        const fileStat = await vscode.workspace.fs.stat(secondLevelUri);
        if (fileStat.type === vscode.FileType.Directory) {
          return { firstLevelUri, secondLevelUri };
        }
      } catch (error: any) {
        // Do nothing
      }
    }

    return { firstLevelUri, secondLevelUri: undefined };
  }

  private addDiscoveredItems(
    testItems: ServerTestItem[],
    parent: vscode.TestItem,
  ) {
    testItems.forEach((item) => {
      const testItem = this.testController.createTestItem(
        item.id,
        item.label,
        vscode.Uri.parse(item.uri),
      );

      testItem.canResolveChildren = item.children.length > 0;
      const start = item.range.start;
      const end = item.range.end;

      testItem.range = new vscode.Range(
        new vscode.Position(start.line, start.character),
        new vscode.Position(end.line, end.character),
      );

      const serverTags = item.tags.map((tag) => new vscode.TestTag(tag));

      testItem.tags = testItem.canResolveChildren
        ? [TEST_GROUP_TAG, DEBUG_TAG, ...serverTags]
        : [DEBUG_TAG, ...serverTags];

      parent.children.add(testItem);

      if (testItem.canResolveChildren) {
        this.addDiscoveredItems(item.children, testItem);
      }
    });
  }

  private recursivelyFilter(
    item: vscode.TestItem,
    exclusions: ReadonlyArray<vscode.TestItem>,
  ): LspTestItem | null {
    // If the item is excluded, then remove it directly
    if (exclusions.includes(item)) {
      return null;
    }

    const childItems: LspTestItem[] = [];

    // Recursively filter the children
    item.children.forEach((child) => {
      const filteredChild = this.recursivelyFilter(child, exclusions);

      if (filteredChild) {
        childItems.push(filteredChild);
      }
    });

    // If this current item had children, but they were all filtered out by exclusions, then we cannot add this item to
    // the included list or we're going to run unintended tests. For example, if all examples have been filtered out for
    // a particular file, we should not include the test item for the file itself in the list, or else we will run all
    // tests for that file and disregard the exclusions
    if (item.children.size > 0 && childItems.length === 0) {
      return null;
    }

    const lspTestItem: LspTestItem = {
      id: item.id,
      label: item.label,
      uri: item.uri!.toString(),
      tags: item.tags.map((tag) => tag.id),
      children: [],
    };

    if (item.range) {
      (lspTestItem as ServerTestItem).range = {
        start: {
          line: item.range.start.line,
          character: item.range.start.character,
        },
        end: {
          line: item.range.end.line,
          character: item.range.end.character,
        },
      };
    }

    // If none of the item's children were excluded, then we want to execute that entire group of tests in one go. For
    // example, if a test class has 3 examples and none of them were excluded, we can simply execute the test class
    // entirely.
    //
    // If the children of the item have been partially filtered, then we need to include which items we should execute
    // in the list
    if (item.children.size !== childItems.length) {
      lspTestItem.children = childItems;
    }

    return lspTestItem;
  }

  private testItemToServerItem(item: vscode.TestItem): LspTestItem {
    const children: LspTestItem[] = [];

    item.children.forEach((child) => {
      children.push(this.testItemToServerItem(child));
    });

    let range;
    if (item.range) {
      range = {
        start: {
          line: item.range.start.line,
          character: item.range.start.character,
        },
        end: {
          line: item.range.end.line,
          character: item.range.end.character,
        },
      };
    }

    return {
      id: item.id,
      label: item.label,
      uri: item.uri!.toString(),
      range,
      children,
      tags: item.tags.map((tag) => tag.id),
    };
  }

  // This method spawns the process that will run tests and registers a JSON RPC connection to listen for events about
  // what's happening during the execution, updating the state of test items in the run
  private async runCommandWithStreamingUpdates(
    run: vscode.TestRun,
    command: string,
    env: NodeJS.ProcessEnv,
    cwd: string,
    token: vscode.CancellationToken,
  ) {
    await new Promise<void>((resolve, reject) => {
      const promises: Promise<void>[] = [];

      const abortController = new AbortController();
      token.onCancellationRequested(() => {
        run.appendOutput("\r\nTest run cancelled.");
        abortController.abort();
      });

      // Use JSON RPC to communicate with the process executing the tests
      const testProcess = spawn(command, {
        env,
        stdio: ["pipe", "pipe", "pipe"],
        shell: true,
        signal: abortController.signal,
        cwd,
      });
      const connection = rpc.createMessageConnection(
        new rpc.StreamMessageReader(testProcess.stdout),
        new rpc.StreamMessageWriter(testProcess.stdin),
      );

      const disposables: vscode.Disposable[] = [];
      let errorMessage = "";

      testProcess.stderr.on("data", (data) => {
        const stringData = data.toString();
        errorMessage += stringData;
        run.appendOutput(stringData);
      });

      // Handle the execution end
      testProcess.on("exit", () => {
        Promise.all(promises)
          .then(() => {
            disposables.forEach((disposable) => disposable.dispose());
            connection.end();
            connection.dispose();
            resolve();
          })
          .catch((err) => {
            reject(err);
          });
      });

      // Handle the JSON events being emitted by the tests
      disposables.push(
        connection.onNotification(NOTIFICATION_TYPES.start, (params) => {
          promises.push(
            this.findTestItem(params.id, vscode.Uri.parse(params.uri)).then(
              (test) => {
                if (test) {
                  run.started(test);
                }
              },
            ),
          );
        }),
      );

      disposables.push(
        connection.onNotification(NOTIFICATION_TYPES.pass, (params) => {
          promises.push(
            this.findTestItem(params.id, vscode.Uri.parse(params.uri)).then(
              (test) => {
                if (test) {
                  run.passed(test);
                }
              },
            ),
          );
        }),
      );

      disposables.push(
        connection.onNotification(NOTIFICATION_TYPES.fail, (params) => {
          promises.push(
            this.findTestItem(params.id, vscode.Uri.parse(params.uri)).then(
              (test) => {
                if (test) {
                  run.failed(test, new vscode.TestMessage(params.message));
                }
              },
            ),
          );
        }),
      );

      disposables.push(
        connection.onNotification(NOTIFICATION_TYPES.error, (params) => {
          promises.push(
            this.findTestItem(params.id, vscode.Uri.parse(params.uri)).then(
              (test) => {
                if (test) {
                  run.errored(test, new vscode.TestMessage(params.message));
                }
              },
            ),
          );
        }),
      );

      disposables.push(
        connection.onNotification(NOTIFICATION_TYPES.skip, (params) => {
          promises.push(
            this.findTestItem(params.id, vscode.Uri.parse(params.uri)).then(
              (test) => {
                if (test) {
                  run.skipped(test);
                }
              },
            ),
          );
        }),
      );

      disposables.push(
        connection.onNotification(NOTIFICATION_TYPES.appendOutput, (params) => {
          run.appendOutput(params.message);
        }),
      );

      // Start listening for events
      connection.listen();
    });
  }
}
