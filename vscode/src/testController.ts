import { exec } from "child_process";
import { promisify } from "util";

import * as vscode from "vscode";
import { CodeLens } from "vscode-languageclient/node";

import { Workspace } from "./workspace";

const asyncExec = promisify(exec);

interface CodeLensData {
  type: string;
  // eslint-disable-next-line @typescript-eslint/naming-convention
  group_id: number;
  id?: number;
  kind: string;
}

export class TestController {
  private readonly testController: vscode.TestController;
  private readonly testCommands: WeakMap<vscode.TestItem, string>;
  private readonly testRunProfile: vscode.TestRunProfile;
  private readonly testDebugProfile: vscode.TestRunProfile;
  private readonly debugTag: vscode.TestTag = new vscode.TestTag("debug");
  private terminal: vscode.Terminal | undefined;
  private readonly telemetry: vscode.TelemetryLogger;
  // We allow the timeout to be configured in seconds, but exec expects it in milliseconds
  private readonly testTimeout = vscode.workspace
    .getConfiguration("rubyLsp")
    .get("testTimeout") as number;

  private readonly currentWorkspace: () => Workspace | undefined;

  constructor(
    context: vscode.ExtensionContext,
    telemetry: vscode.TelemetryLogger,
    currentWorkspace: () => Workspace | undefined,
  ) {
    this.telemetry = telemetry;
    this.currentWorkspace = currentWorkspace;
    this.testController = vscode.tests.createTestController(
      "rubyTests",
      "Ruby Tests",
    );

    this.testCommands = new WeakMap<vscode.TestItem, string>();

    this.testRunProfile = this.testController.createRunProfile(
      "Run",
      vscode.TestRunProfileKind.Run,
      async (request, token) => {
        await this.runHandler(request, token);
      },
      true,
    );

    this.testDebugProfile = this.testController.createRunProfile(
      "Debug",
      vscode.TestRunProfileKind.Debug,
      async (request, token) => {
        await this.debugHandler(request, token);
      },
      false,
      this.debugTag,
    );

    context.subscriptions.push(
      this.testController,
      this.testDebugProfile,
      this.testRunProfile,
      vscode.window.onDidCloseTerminal((terminal: vscode.Terminal): void => {
        if (terminal === this.terminal) this.terminal = undefined;
      }),
    );
  }

  createTestItems(response: CodeLens[]) {
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
        testItem.tags = [...testItem.tags, this.debugTag];
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
}
