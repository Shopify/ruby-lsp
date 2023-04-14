import { exec } from "child_process";
import { promisify } from "util";

import * as vscode from "vscode";
import { CodeLens } from "vscode-languageclient/node";

import { Ruby } from "./ruby";
import { Command } from "./status";

const asyncExec = promisify(exec);

export class TestController {
  private testController: vscode.TestController;
  private testRunProfile: vscode.TestRunProfile;
  private workingFolder: string;
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

    this.testRunProfile = this.testController.createRunProfile(
      "Run",
      vscode.TestRunProfileKind.Run,
      (request, token) => {
        this.runHandler(request, token);
      },
      true
    );

    context.subscriptions.push(
      this.testController,
      vscode.commands.registerCommand(
        Command.RunTest,
        (_path, name, _command) => {
          this.runOnClick(name);
        }
      )
    );
  }

  createTestItems(response: CodeLens[]) {
    this.testController.items.forEach((test) => {
      this.testController.items.delete(test.id);
    });

    let classTest: vscode.TestItem;
    const uri = vscode.Uri.from({
      scheme: "file",
      path: response[0].command!.arguments![0],
    });

    response.forEach((res) => {
      if (res.data.type === "test") {
        const [_, name, command, location] = res.command!.arguments!;
        const testItem: vscode.TestItem = this.testController.createTestItem(
          name,
          name,
          uri
        );

        testItem.description = command;
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
      }
    });
  }

  async runHandler(
    request: vscode.TestRunRequest,
    token: vscode.CancellationToken
  ) {
    const run = this.testController.createTestRun(request, undefined, false);
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

      const start = Date.now();
      try {
        await this.assertTestPasses(test);
        run.passed(test, Date.now() - start);
      } catch (err: any) {
        run.failed(
          test,
          new vscode.TestMessage(err.message),
          Date.now() - start
        );
      }

      test.children.forEach((test) => queue.push(test));
    }

    // Make sure to end the run after all tests have been executed
    run.end();
  }

  async assertTestPasses(test: vscode.TestItem) {
    try {
      await asyncExec(test.description!, {
        cwd: this.workingFolder,
        env: this.ruby.env,
      });
    } catch (error: any) {
      const errorArr = error.stdout.split("\n");

      if (errorArr[0] === "") {
        // Minitest
        throw new Error(errorArr.slice(10, errorArr.length - 2).join("\n"));
      } else {
        // test-unit
        throw new Error(errorArr.slice(4, errorArr.length - 9).join("\n"));
      }
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

    const testRun = new vscode.TestRunRequest([test]);
    this.runHandler(testRun, tokenSource.token);
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
