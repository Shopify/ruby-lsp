import { exec } from "child_process";
import { promisify } from "util";

import * as vscode from "vscode";
import { CodeLens } from "vscode-languageclient/node";

import { Ruby } from "./ruby";
import { Command } from "./status";
import { Telemetry } from "./telemetry";

const asyncExec = promisify(exec);

const TERMINAL_NAME = "Ruby LSP: Run test";

export class TestController {
  private testController: vscode.TestController;
  private testCommands: WeakMap<vscode.TestItem, string>;
  private testRunProfile: vscode.TestRunProfile;
  private testDebugProfile: vscode.TestRunProfile;
  private debugTag: vscode.TestTag = new vscode.TestTag("debug");
  private workingFolder: string;
  private terminal: vscode.Terminal | undefined;
  private ruby: Ruby;
  private telemetry: Telemetry;

  constructor(
    context: vscode.ExtensionContext,
    workingFolder: string,
    ruby: Ruby,
    telemetry: Telemetry
  ) {
    this.workingFolder = workingFolder;
    this.ruby = ruby;
    this.telemetry = telemetry;

    this.testController = vscode.tests.createTestController(
      "rubyTests",
      "Ruby Tests"
    );

    this.testCommands = new WeakMap<vscode.TestItem, string>();

    this.testRunProfile = this.testController.createRunProfile(
      "Run",
      vscode.TestRunProfileKind.Run,
      (request, token) => {
        this.runHandler(request, token);
      },
      true
    );

    this.testDebugProfile = this.testController.createRunProfile(
      "Debug",
      vscode.TestRunProfileKind.Debug,
      (request, token) => {
        this.debugHandler(request, token);
      },
      false,
      this.debugTag
    );

    vscode.commands.executeCommand("testing.clearTestResults");
    vscode.window.onDidCloseTerminal((terminal: vscode.Terminal): void => {
      if (terminal === this.terminal) this.terminal = undefined;
    });

    context.subscriptions.push(
      this.testController,
      vscode.commands.registerCommand(
        Command.RunTest,
        (_path, name, _command) => {
          this.runOnClick(name);
        }
      ),
      vscode.commands.registerCommand(
        Command.RunTestInTerminal,
        this.runTestInTerminal.bind(this)
      ),
      vscode.commands.registerCommand(
        Command.DebugTest,
        this.debugTest.bind(this)
      )
    );
  }

  createTestItems(response: CodeLens[]) {
    this.testController.items.forEach((test) => {
      this.testController.items.delete(test.id);
      this.testCommands.delete(test);
    });

    let classTest: vscode.TestItem;
    const uri = vscode.Uri.from({
      scheme: "file",
      path: response[0].command!.arguments![0],
    });

    response.forEach((res) => {
      const [_, name, command, location] = res.command!.arguments!;
      const testItem: vscode.TestItem = this.testController.createTestItem(
        name,
        name,
        uri
      );

      if (res.data?.kind) {
        testItem.tags = [new vscode.TestTag(res.data.kind)];
      } else if (name.startsWith("test_")) {
        // Older Ruby LSP versions may not include 'kind' so we try infer it from the name.
        testItem.tags = [new vscode.TestTag("example")];
      }

      this.testCommands.set(testItem, command);

      testItem.range = new vscode.Range(
        new vscode.Position(location.start_line, location.start_column),
        new vscode.Position(location.end_line, location.end_column)
      );

      // Add test methods as children to the test class so it appears nested in Test explorer
      // and running the test class will run all of the test methods

      if (testItem.tags.find((tag) => tag.id === "example")) {
        testItem.tags = [...testItem.tags, this.debugTag];
        classTest.children.add(testItem);
      } else {
        classTest = testItem;
        classTest.canResolveChildren = true;
        this.testController.items.add(testItem);
      }
    });
  }

  dispose() {
    this.testRunProfile.dispose();
    this.testDebugProfile.dispose();
    this.testController.dispose();
  }

  private debugTest(_path: string, _name: string, command: string) {
    return vscode.debug.startDebugging(undefined, {
      type: "ruby_lsp",
      name: "Debug",
      request: "launch",
      program: command,
      env: { ...this.ruby.env, DISABLE_SPRING: "1" },
    });
  }

  private async runTestInTerminal(
    _path: string,
    _name: string,
    command: string
  ) {
    await this.telemetry.sendCodeLensEvent("test_in_terminal");

    if (this.terminal === undefined) {
      this.terminal = this.getTerminal();
    }

    this.terminal.show();
    this.terminal.sendText(command);
  }

  private getTerminal() {
    const previousTerminal = vscode.window.terminals.find(
      (terminal) => terminal.name === TERMINAL_NAME
    );

    return previousTerminal
      ? previousTerminal
      : vscode.window.createTerminal({
          name: TERMINAL_NAME,
        });
  }

  private async debugHandler(
    request: vscode.TestRunRequest,
    _token: vscode.CancellationToken
  ) {
    await this.telemetry.sendCodeLensEvent("debug");
    const run = this.testController.createTestRun(request, undefined, true);
    const test = request.include![0];

    const start = Date.now();
    await this.debugTest("", "", this.testCommands.get(test)!);
    run.passed(test, Date.now() - start);
    run.end();
  }

  private async runHandler(
    request: vscode.TestRunRequest,
    token: vscode.CancellationToken
  ) {
    await this.telemetry.sendCodeLensEvent("test");
    const run = this.testController.createTestRun(request, undefined, true);
    const queue: vscode.TestItem[] = [];

    if (request.include) {
      request.include.forEach((test) => queue.push(test));
    } else {
      this.testController.items.forEach((test) => queue.push(test));
    }

    while (queue.length > 0 && !token.isCancellationRequested) {
      const test = queue.pop()!;

      if (request.exclude?.includes(test)) {
        continue;
      }

      if (test.tags.find((tag) => tag.id === "example")) {
        const start = Date.now();
        try {
          await this.assertTestPasses(test);
          run.passed(test, Date.now() - start);
        } catch (err: any) {
          const messageArr = err.message.split("\n");

          // Minitest and test/unit outputs are formatted differently so we need to slice the message
          // differently to get an output format that only contains essential information
          // If the first element of the message array is "", we know the output is a Minitest output
          const testMessage =
            messageArr[0] === ""
              ? messageArr.slice(10, messageArr.length - 2).join("\n")
              : messageArr.slice(4, messageArr.length - 9).join("\n");

          run.failed(
            test,
            new vscode.TestMessage(testMessage),
            Date.now() - start
          );
        }
      }

      test.children.forEach((test) => queue.push(test));
    }

    // Make sure to end the run after all tests have been executed
    run.end();
  }

  private async assertTestPasses(test: vscode.TestItem) {
    try {
      await asyncExec(this.testCommands.get(test)!, {
        cwd: this.workingFolder,
        env: this.ruby.env,
      });
    } catch (error: any) {
      throw new Error(error.stdout);
    }
  }

  private async runOnClick(testId: string) {
    const test = this.findTestById(this.testController.items, testId);

    if (!test) return;

    vscode.commands.executeCommand("vscode.revealTestInExplorer", test);
    let tokenSource: vscode.CancellationTokenSource | null =
      new vscode.CancellationTokenSource();

    tokenSource.token.onCancellationRequested(() => {
      tokenSource?.dispose();
      tokenSource = null;

      vscode.window.showInformationMessage("Cancelled the progress");
    });

    const testRun = new vscode.TestRunRequest([test], [], this.testRunProfile);

    this.testRunProfile.runHandler(testRun, tokenSource.token);
  }

  private findTestById(testItems: vscode.TestItemCollection, testId: string) {
    let testItem = testItems.get(testId);

    if (testItem) return testItem;

    testItems.forEach((test) => {
      const childTestItem = this.findTestById(test.children, testId);
      if (childTestItem) testItem = childTestItem;
    });

    return testItem;
  }
}
