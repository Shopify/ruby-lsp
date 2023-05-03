import { exec } from "child_process";
import { promisify } from "util";

import * as vscode from "vscode";
import { CodeLens } from "vscode-languageclient/node";

import { Ruby } from "./ruby";
import { Command } from "./status";

const asyncExec = promisify(exec);

export class TestController {
  private testController: vscode.TestController;
  private testCommands: WeakMap<vscode.TestItem, string>;
  private testRunProfile: vscode.TestRunProfile;
  private workingFolder: string;
  private terminal: vscode.Terminal | undefined;
  private ruby: Ruby;

  constructor(
    context: vscode.ExtensionContext,
    workingFolder: string,
    ruby: Ruby
  ) {
    this.workingFolder = workingFolder;
    this.ruby = ruby;

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

      this.testCommands.set(testItem, command);

      testItem.range = new vscode.Range(
        new vscode.Position(location.start_line, location.start_column),
        new vscode.Position(location.end_line, location.end_column)
      );

      // Add test methods as children to the test class so it appears nested in Test explorer
      // and running the test class will run all of the test methods
      if (name.startsWith("test_")) {
        classTest.children.add(testItem);
      } else {
        classTest = testItem;
        classTest.canResolveChildren = true;
        this.testController.items.add(testItem);
      }
    });
  }

  debugTest(_path: string, _name: string, command: string) {
    return vscode.debug.startDebugging(undefined, {
      type: "ruby_lsp",
      name: "Debug",
      request: "launch",
      program: command,
      env: this.ruby.env,
    });
  }

  runTestInTerminal(_path: string, _name: string, command: string) {
    if (this.terminal === undefined) {
      this.terminal = vscode.window.createTerminal({ name: "Run test" });
    }
    this.terminal.show();
    this.terminal.sendText(command);
  }

  async runHandler(
    request: vscode.TestRunRequest,
    token: vscode.CancellationToken
  ) {
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

      if (test.id.startsWith("test_")) {
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

  async assertTestPasses(test: vscode.TestItem) {
    try {
      await asyncExec(this.testCommands.get(test)!, {
        cwd: this.workingFolder,
        env: this.ruby.env,
      });
    } catch (error: any) {
      throw new Error(error.stdout);
    }
  }

  async runOnClick(testId: string) {
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

  findTestById(testItems: vscode.TestItemCollection, testId: string) {
    let testItem = testItems.get(testId);

    if (testItem) return testItem;

    testItems.forEach((test) => {
      const childTestItem = this.findTestById(test.children, testId);
      if (childTestItem) testItem = childTestItem;
    });

    return testItem;
  }

  dispose() {
    this.testRunProfile.dispose();
    this.testController.dispose();
  }
}
