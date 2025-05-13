import { exec } from "child_process";
import { promisify } from "util";
import path from "path";

import * as vscode from "vscode";
import { CodeLens } from "vscode-languageclient/node";

import { Workspace } from "./workspace";
import { featureEnabled } from "./common";
import { LspTestItem, ResolvedCommands, ServerTestItem } from "./client";
import { LinkedCancellationSource } from "./linkedCancellationSource";
import { Mode, StreamingRunner } from "./streamingRunner";

const asyncExec = promisify(exec);

const NESTED_TEST_DIR_PATTERN = "**/{test,spec,features}/**/";
const TEST_FILE_PATTERN = `${NESTED_TEST_DIR_PATTERN}{*_test.rb,test_*.rb,*_spec.rb,*.feature}`;

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

const RUN_PROFILE_LABEL = "Run";
const RUN_IN_TERMINAL_PROFILE_LABEL = "Run in terminal";
const DEBUG_PROFILE_LABEL = "Debug";
const COVERAGE_PROFILE_LABEL = "Coverage";

export class TestController {
  // Only public for testing
  readonly testController: vscode.TestController;
  readonly testRunProfile: vscode.TestRunProfile;
  readonly runInTerminalProfile: vscode.TestRunProfile;
  readonly coverageProfile: vscode.TestRunProfile;
  readonly testDebugProfile: vscode.TestRunProfile;
  private readonly testCommands: WeakMap<vscode.TestItem, string>;
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
  private readonly coverageData = new WeakMap<
    vscode.FileCoverage,
    vscode.FileCoverageDetail[]
  >();

  private readonly runner: StreamingRunner;

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
    this.runner = new StreamingRunner(
      context,
      this.findTestItem.bind(this),
      this.testController.createTestRun.bind(this.testController),
    );

    if (this.fullDiscovery) {
      this.testController.resolveHandler = this.resolveHandler.bind(this);
      this.testController.refreshHandler = this.refreshHandler.bind(this);
    }

    this.testCommands = new WeakMap<vscode.TestItem, string>();

    this.testRunProfile = this.testController.createRunProfile(
      RUN_PROFILE_LABEL,
      vscode.TestRunProfileKind.Run,
      this.fullDiscovery ? this.runTest.bind(this) : this.runHandler.bind(this),
      true,
      undefined,
      true,
    );

    this.testDebugProfile = this.testController.createRunProfile(
      DEBUG_PROFILE_LABEL,
      vscode.TestRunProfileKind.Debug,
      this.fullDiscovery
        ? this.runTest.bind(this)
        : this.debugHandler.bind(this),
      false,
      DEBUG_TAG,
    );

    this.coverageProfile = this.testController.createRunProfile(
      COVERAGE_PROFILE_LABEL,
      vscode.TestRunProfileKind.Coverage,
      this.fullDiscovery
        ? this.runTest.bind(this)
        : async () => {
            await vscode.window.showInformationMessage(
              `Running tests with coverage requires the new explorer implementation,
               which is currently under development.
               If you wish to enable it, set the "fullTestDiscovery" feature flag to "true"`,
            );
          },
      false,
    );

    // This method is invoked when a document is opened in the UI to gather any additional details about coverage for
    // inline decorations. We save all of the available details in the `coverageData` map ahead of time, so we just need
    // to return the existing data
    this.coverageProfile.loadDetailedCoverage = async (
      _testRun,
      fileCoverage,
      _token,
    ) => {
      return this.coverageData.get(fileCoverage)!;
    };

    this.runInTerminalProfile = this.testController.createRunProfile(
      RUN_IN_TERMINAL_PROFILE_LABEL,
      vscode.TestRunProfileKind.Run,
      this.runTest.bind(this),
      false,
    );

    const testFileWatcher =
      vscode.workspace.createFileSystemWatcher(TEST_FILE_PATTERN);

    const nestedTestDirWatcher = vscode.workspace.createFileSystemWatcher(
      NESTED_TEST_DIR_PATTERN,
      true,
      true,
      false,
    );

    context.subscriptions.push(
      this.testController,
      this.testDebugProfile,
      this.testRunProfile,
      this.coverageProfile,
      this.runner,
      this.runInTerminalProfile,
      vscode.window.onDidCloseTerminal((terminal: vscode.Terminal): void => {
        if (terminal === this.terminal) this.terminal = undefined;
      }),
      testFileWatcher,
      nestedTestDirWatcher,
      testFileWatcher.onDidCreate(async (uri) => {
        const workspace = vscode.workspace.getWorkspaceFolder(uri);

        if (!workspace || !vscode.workspace.workspaceFolders) {
          return;
        }

        const initialCollection =
          vscode.workspace.workspaceFolders.length === 1
            ? this.testController.items
            : this.testController.items.get(workspace.uri.toString())?.children;

        if (!initialCollection) {
          return;
        }

        await this.addTestItemsForFile(uri, workspace, initialCollection);
      }),
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
      nestedTestDirWatcher.onDidDelete(async (uri) => {
        const pathParts = uri.fsPath.split(path.sep);
        if (pathParts.includes(".git")) {
          return;
        }

        const parentItem = await this.getParentTestItem(uri);

        if (parentItem) {
          parentItem.children.delete(uri.toString());
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

  /**
   * @deprecated To be removed once the new test explorer is fully rolled out
   */
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

  /**
   * @deprecated by {@link runViaCommand}. To be removed once the new test explorer is fully rolled out
   */
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

  /**
   * @deprecated by {@link runViaCommand}. To be removed once the new test explorer is fully rolled out
   */
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

  /**
   * @deprecated by {@link runViaCommand}. To be removed once the new test explorer is fully rolled out
   */
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

  // Method to run tests in any profile through code lens buttons
  async runViaCommand(path: string, name: string, mode: Mode) {
    const uri = vscode.Uri.file(path);
    const testItem = await this.findTestItem(name, uri);
    if (!testItem) return;

    await vscode.commands.executeCommand(
      "vscode.revealTestInExplorer",
      testItem,
    );
    const tokenSource = new vscode.CancellationTokenSource();

    tokenSource.token.onCancellationRequested(async () => {
      tokenSource.dispose();
      await vscode.window.showInformationMessage("Cancelled the progress");
    });

    let profile;

    switch (mode) {
      case Mode.Debug:
        profile = this.testDebugProfile;
        break;
      case Mode.RunInTerminal:
        profile = this.runInTerminalProfile;
        break;
      default:
        profile = this.testRunProfile;
        break;
    }

    const request = new vscode.TestRunRequest([testItem], [], profile);
    return this.runTest(request, tokenSource.token);
  }

  async runTest(
    request: vscode.TestRunRequest,
    token: vscode.CancellationToken,
  ) {
    this.telemetry.logUsage("ruby_lsp.test_explorer", {
      type: "counter",
      attributes: {
        label: request.profile?.label || RUN_PROFILE_LABEL,
        vscodemachineid: vscode.env.machineId,
        continuousMode: request.continuous ?? false,
      },
    });
    if (request.continuous) {
      const disposables: vscode.Disposable[] = [];

      const testFileWatcher = vscode.workspace.createFileSystemWatcher(
        TEST_FILE_PATTERN,
        true,
        false,
        true,
      );

      disposables.push(
        testFileWatcher,
        testFileWatcher.onDidChange(async () => {
          const continuousRequest = new vscode.TestRunRequest(
            request.include,
            request.exclude,
            request.profile,
            false,
            request.preserveFocus,
          );

          await this.handleTests(continuousRequest, token);
        }),
      );

      disposables.push(
        token.onCancellationRequested(() => {
          disposables.forEach((disposable) => disposable.dispose());
        }),
      );
    } else {
      await this.handleTests(request, token);
    }
  }

  // Public for testing purposes. Finds a test item based on its ID and URI
  async findTestItem(id: string, uri: vscode.Uri, line?: number) {
    if (this.testController.items.size === 0) {
      // Discover and test items immediately if the test explorer hasn't been expanded
      await this.resolveHandler(undefined);
    }

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
    return this.findTestInGroup(id, testFileItem, line);
  }

  async activate() {
    await this.runner.activate();
  }

  get streamingPort() {
    return this.runner.tcpPort;
  }

  private async refreshHandler(_token: vscode.CancellationToken) {
    this.testController.items.replace([]);
    this.testController.invalidateTestResults();
    await this.testController.resolveHandler!(undefined);
  }

  private async handleTests(
    request: vscode.TestRunRequest,
    token: vscode.CancellationToken,
  ) {
    const run = this.testController.createTestRun(request);

    // Gather all included test items
    const items: vscode.TestItem[] = [];
    if (request.include) {
      request.include.forEach((test) => items.push(test));
    } else {
      this.testController.items.forEach((test) => items.push(test));
    }

    await this.discoverFrameworkTag(items);

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

    const linkedCancellationSource = new LinkedCancellationSource(
      token,
      run.token,
    );

    for (const [workspaceFolder, testItems] of workspaceToTestItems) {
      if (linkedCancellationSource.isCancellationRequested()) {
        break;
      }

      // Build the test item parameters that we send to the server, filtering out exclusions. Then ask the server for
      // the resolved test commands
      const requestTestItems = this.buildRequestTestItems(
        testItems,
        request.exclude,
      );
      const workspace = await this.getOrActivateWorkspace(workspaceFolder);

      if (
        !workspace.lspClient?.initializeResult?.capabilities.experimental
          ?.full_test_discovery
      ) {
        run.appendOutput(
          `The version of the Ruby LSP server being used by ${workspaceFolder.name} does not support the new
           test explorer functionality. Please make sure you are using the latest version of the server.
           See https://shopify.github.io/ruby-lsp/troubleshooting.html#outdated-version for more information.`,
        );
        break;
      }

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

      const profile = request.profile;

      if (
        !profile ||
        profile.label === RUN_PROFILE_LABEL ||
        profile.label === RUN_IN_TERMINAL_PROFILE_LABEL ||
        profile.label === COVERAGE_PROFILE_LABEL
      ) {
        await this.executeTestCommands(
          response,
          workspace,
          run,
          profile,
          linkedCancellationSource,
        );
      } else if (profile.label === DEBUG_PROFILE_LABEL) {
        await this.debugTestCommands(
          response,
          workspace,
          run,
          linkedCancellationSource,
        );
      }
    }

    run.end();
    linkedCancellationSource.dispose();
  }

  // When trying to a test file or directory, we need to know which framework is used by tests inside of it to resolve
  // the command correctly. This method will resolve the first test file with children inside to determine the framework
  // and then set that to all parents
  private async discoverFrameworkTag(items: vscode.TestItem[]) {
    const missingFramework = items.filter((item) => {
      return !item.tags.some((tag) => tag.id.startsWith("framework"));
    });

    if (missingFramework.length === 0) {
      return;
    }

    for (const item of missingFramework) {
      let testFileItem = item;

      while (!testFileItem.tags.some((tag) => tag === TEST_FILE_TAG)) {
        let firstChild: vscode.TestItem | undefined;

        testFileItem.children.forEach((child) => {
          if (firstChild === undefined) firstChild = child;
        });

        testFileItem = firstChild!;
      }

      // Handle the case where the test file is empty and has no children
      await this.resolveHandler(testFileItem);
      this.setFrameworkTagInAllParents(testFileItem);
    }
  }

  private setFrameworkTagInAllParents(item: vscode.TestItem) {
    const tag = item.tags.find((tag) => tag.id.startsWith("framework"))!;
    let parent = item.parent;

    while (parent) {
      if (!parent.tags.some((tag) => tag.id.startsWith("framework"))) {
        parent.tags = [...parent.tags, tag];
      }

      parent = parent.parent;
    }
  }

  // Execute all of the test commands reported by the server in the background using JSON RPC to receive streaming
  // updates
  private async executeTestCommands(
    response: ResolvedCommands,
    workspace: Workspace,
    run: vscode.TestRun,
    profile: vscode.TestRunProfile | undefined,
    linkedCancellationSource: LinkedCancellationSource,
  ) {
    // Require the custom JSON RPC reporters through RUBYOPT. We cannot use Ruby's `-r` flag because the moment the
    // test framework is loaded, it might change which options are accepted. For example, if we append `-r` after the
    // file path for Minitest, it will fail with unrecognized argument errors
    const commonOpts = `-rbundler/setup ${response.reporterPaths?.map((path) => `-r${path}`).join(" ")}`;
    const rubyOpt = workspace.ruby.env.RUBYOPT
      ? `${workspace.ruby.env.RUBYOPT} ${commonOpts}`
      : commonOpts;

    const runnerMode = profile === this.coverageProfile ? "coverage" : "run";
    const mode =
      profile === this.runInTerminalProfile ? Mode.RunInTerminal : Mode.Run;

    for await (const command of response.commands) {
      try {
        await this.runner.execute(
          run,
          command,
          {
            ...workspace.ruby.env,
            RUBY_LSP_TEST_RUNNER: runnerMode,
            RUBYOPT: rubyOpt,
          },
          workspace,
          mode,
          linkedCancellationSource,
        );
      } catch (error: any) {
        await vscode.window.showErrorMessage(
          `Running ${command} failed: ${error.message}`,
        );
      }
    }

    if (profile === this.coverageProfile) {
      run.appendOutput("\r\n\r\nProcessing test coverage results...\r\n\r\n");
      await this.processTestCoverageResults(run, workspace.workspaceFolder);
    }
  }

  // Launches the debugger for the test commands reported by the server. This mode of execution does not support the
  // JSON RPC streaming updates as the debugger uses the stdio pipes to communicate with the editor
  private async debugTestCommands(
    response: ResolvedCommands,
    workspace: Workspace,
    run: vscode.TestRun,
    linkedCancellationSource: LinkedCancellationSource,
  ) {
    for (const command of response.commands) {
      if (linkedCancellationSource.isCancellationRequested()) {
        break;
      }
      const commonOpts = `-rbundler/setup ${response.reporterPaths?.map((path) => `-r${path}`).join(" ")}`;
      const rubyOpt = workspace.ruby.env.RUBYOPT
        ? `${workspace.ruby.env.RUBYOPT} ${commonOpts}`
        : commonOpts;

      await this.runner.execute(
        run,
        command,
        {
          ...workspace.ruby.env,
          RUBY_LSP_TEST_RUNNER: "debug",
          RUBYOPT: rubyOpt,
        },
        workspace,
        Mode.Debug,
        linkedCancellationSource,
      );
    }
  }

  private findTestInGroup(
    id: string,
    group: vscode.TestItem,
    line: number | undefined,
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

    // If we found the exact item, return it
    const target = found.children.get(id);
    if (target) {
      return target;
    }

    // If the ID we're looking for starts with the found item's ID suffixed by a `::`, it means that there are more
    // groups nested inside and we can continue searching
    if (id.startsWith(`${found.id}::`)) {
      return this.findTestInGroup(id, found, line);
    }

    if (!line) {
      return;
    }

    // If neither of the previous are true, then this test is dynamically defined and we need to create the items for it
    // automatically
    const label = id.split("#")[1]!;
    const testItem = this.testController.createTestItem(
      id,
      `★ ${label}`,
      found.uri,
    );

    testItem.description = "dynamic test";

    testItem.range = new vscode.Range(
      new vscode.Position(line, 0),
      new vscode.Position(line, 1),
    );

    const frameworkTag = found.tags.find((tag) =>
      tag.id.startsWith("framework"),
    );

    testItem.tags = frameworkTag ? [DEBUG_TAG, frameworkTag] : [DEBUG_TAG];
    found.children.add(testItem);
    return testItem;
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

        if (
          !workspace.lspClient?.initializeResult?.capabilities.experimental
            ?.full_test_discovery
        ) {
          await vscode.window.showWarningMessage(
            `The version of the Ruby LSP server being used by ${workspaceFolder.name} does not support the new
             test explorer functionality. Please make sure you are using the latest version of the server.
             See https://shopify.github.io/ruby-lsp/troubleshooting.html#outdated-version for more information.`,
          );
          return;
        }

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
      await this.addTestItemsForFile(uri, workspaceFolder, initialCollection);
    }
  }

  private async addTestItemsForFile(
    uri: vscode.Uri,
    workspaceFolder: vscode.WorkspaceFolder,
    initialCollection: vscode.TestItemCollection,
  ) {
    const fileName = path.basename(uri.fsPath);
    const relativePath = vscode.workspace.asRelativePath(uri, false);
    const pathParts = relativePath.split(path.sep);

    if (this.shouldSkipTestFile(fileName, pathParts)) {
      return;
    }

    // Get the appropriate collection to add the test file to, creating any necessary hierarchy levels
    const { firstLevel, secondLevel } = await this.getOrCreateHierarchyLevels(
      uri,
      workspaceFolder,
      initialCollection,
    );

    const finalItem = secondLevel ?? firstLevel;
    const testItem = this.testController.createTestItem(
      uri.toString(),
      path.relative(finalItem.uri!.fsPath, uri.fsPath),
      uri,
    );

    testItem.canResolveChildren = true;
    testItem.tags = [TEST_FILE_TAG, DEBUG_TAG];
    finalItem.children.add(testItem);

    return { firstLevel, secondLevel, testItem };
  }

  private async detectHierarchyLevels(
    uri: vscode.Uri,
    workspaceFolder: vscode.WorkspaceFolder,
  ): Promise<{
    firstLevel: { name: string; uri: vscode.Uri };
    secondLevel?: { name: string; uri: vscode.Uri };
  }> {
    // Find the position of the `test/spec/feature` directory. There may be many in applications that are divided by
    // components, so we want to show each individual test directory as a separate item
    const relativePath = vscode.workspace.asRelativePath(uri, false);
    const pathParts = relativePath.split(path.sep);
    const dirPosition = this.testDirectoryPosition(pathParts);

    // Get the first level test directory item (e.g., test/, spec/, features/)
    const firstLevelName = pathParts.slice(0, dirPosition + 1).join(path.sep);
    const firstLevelUri = vscode.Uri.joinPath(
      workspaceFolder.uri,
      firstLevelName,
    );

    // In Rails apps, it's also very common to divide the test directory into a second hierarchy level, like models or
    // controllers. Here we try to find out if there is a second level, allowing users to run all tests for models for
    // example
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
          return {
            firstLevel: { name: firstLevelName, uri: firstLevelUri },
            secondLevel: { name: secondLevelName, uri: secondLevelUri },
          };
        }
      } catch (error: any) {
        // Do nothing
      }
    }

    return { firstLevel: { name: firstLevelName, uri: firstLevelUri } };
  }

  private async getOrCreateHierarchyLevels(
    uri: vscode.Uri,
    workspaceFolder: vscode.WorkspaceFolder,
    collection: vscode.TestItemCollection,
  ): Promise<{
    firstLevel: vscode.TestItem;
    secondLevel: vscode.TestItem | undefined;
  }> {
    const { firstLevel, secondLevel } = await this.detectHierarchyLevels(
      uri,
      workspaceFolder,
    );

    // Get or create the first level test directory item
    let firstLevelItem = collection.get(firstLevel.uri.toString());
    if (!firstLevelItem) {
      firstLevelItem = this.testController.createTestItem(
        firstLevel.uri.toString(),
        firstLevel.name,
        firstLevel.uri,
      );
      firstLevelItem.tags = [TEST_DIR_TAG, DEBUG_TAG];
      collection.add(firstLevelItem);
    }

    // If we have a second level, get or create it
    if (secondLevel) {
      let secondLevelItem = firstLevelItem.children.get(
        secondLevel.uri.toString(),
      );

      if (!secondLevelItem) {
        secondLevelItem = this.testController.createTestItem(
          secondLevel.uri.toString(),
          secondLevel.name,
          secondLevel.uri,
        );
        secondLevelItem.tags = [TEST_DIR_TAG, DEBUG_TAG];
        firstLevelItem.children.add(secondLevelItem);
      }

      return {
        firstLevel: firstLevelItem,
        secondLevel: secondLevelItem,
      };
    }

    return {
      firstLevel: firstLevelItem,
      secondLevel: undefined,
    };
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
    return new vscode.RelativePattern(workspaceFolder, TEST_FILE_PATTERN);
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

      const workspaceTestItem = initialCollection.get(
        workspaceFolder.uri.toString(),
      );
      initialCollection = workspaceTestItem!.children;

      if (initialCollection.size === 0) {
        await this.resolveHandler(workspaceTestItem);
      }
    }

    // Get the hierarchy levels and find the appropriate test item
    const { firstLevel, secondLevel } = await this.detectHierarchyLevels(
      uri,
      workspaceFolder,
    );

    let item = initialCollection.get(firstLevel.uri.toString());
    if (secondLevel) {
      item = item?.children.get(secondLevel.uri.toString());
    }

    return item;
  }

  private addDiscoveredItems(
    testItems: ServerTestItem[],
    parent: vscode.TestItem,
  ) {
    if (testItems.length === 0) {
      return;
    }

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

    const framework = testItems[0].tags.find((tag) =>
      tag.startsWith("framework"),
    );

    if (!framework) {
      return;
    }

    if (!parent.tags.some((tag) => tag.id.startsWith("framework"))) {
      parent.tags = [...parent.tags, new vscode.TestTag(framework)];
    }
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

  private async processTestCoverageResults(
    run: vscode.TestRun,
    workspaceFolder: vscode.WorkspaceFolder,
  ) {
    try {
      // Read the coverage data generated by the server during test execution
      const rawData = await vscode.workspace.fs.readFile(
        vscode.Uri.joinPath(
          workspaceFolder.uri,
          ".ruby-lsp",
          "coverage_result.json",
        ),
      );

      const data: Record<string, vscode.FileCoverageDetail[]> = JSON.parse(
        rawData.toString(),
      );

      // Add the coverage data for all files as part of this run
      Object.entries(data).forEach(([uri, coverageData]) => {
        const fileCoverage = vscode.FileCoverage.fromDetails(
          vscode.Uri.parse(uri),
          coverageData,
        );

        run.addCoverage(fileCoverage);
        this.coverageData.set(fileCoverage, coverageData);
      });
    } catch (error: any) {
      run.appendOutput(`Failed to process coverage results: ${error.message}`);
    }
  }
}
