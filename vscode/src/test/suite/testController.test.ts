import * as assert from "assert";
import path from "path";
import fs from "fs";
import os from "os";

import * as vscode from "vscode";
import { CodeLens } from "vscode-languageclient/node";
import { afterEach } from "mocha";
import sinon from "sinon";

import { TestController } from "../../testController";
import * as common from "../../common";

import { FAKE_TELEMETRY } from "./fakeTelemetry";

suite("TestController", () => {
  const workspacePath = path.dirname(
    path.dirname(path.dirname(path.dirname(__dirname))),
  );
  const workspaceUri = vscode.Uri.file(workspacePath);
  const workspaceFolder: vscode.WorkspaceFolder = {
    uri: workspaceUri,
    name: path.basename(workspaceUri.fsPath),
    index: 0,
  };
  const context = {
    extensionMode: vscode.ExtensionMode.Test,
    subscriptions: [],
    workspaceState: {
      get: (_name: string) => undefined,
      update: (_name: string, _value: any) => Promise.resolve(),
    },
  } as unknown as vscode.ExtensionContext;

  afterEach(() => {
    context.subscriptions.forEach((subscription) => subscription.dispose());
  });

  test("createTestItems doesn't break when there's a missing group", () => {
    const controller = new TestController(
      context,
      FAKE_TELEMETRY,
      () => undefined,
    );

    const codeLensItems: CodeLens[] = [
      {
        range: new vscode.Range(0, 0, 10, 10),
        command: {
          title: "Run",
          command: common.Command.RunTest,
          arguments: [
            "test/fake_test.rb",
            "test_do_something",
            "bundle exec ruby -Itest test/fake_test.rb --name FakeTest#test_do_something",
            {
              /* eslint-disable @typescript-eslint/naming-convention */
              start_line: 0,
              start_column: 0,
              end_line: 10,
              end_column: 10,
              /* eslint-enable @typescript-eslint/naming-convention */
            },
          ],
        },
        data: {
          type: "test",
          // eslint-disable-next-line @typescript-eslint/naming-convention
          group_id: 100,
          kind: "example",
        },
      },
    ];

    assert.doesNotThrow(() => {
      controller.createTestItems(codeLensItems);
    });
  });

  test("populates test structure directly if there's only one workspace", async () => {
    const stub = sinon.stub(common, "featureEnabled").returns(true);
    const controller = new TestController(
      context,
      FAKE_TELEMETRY,
      () => undefined,
    );
    stub.restore();

    const workspacesStub = sinon
      .stub(vscode.workspace, "workspaceFolders")
      .get(() => [workspaceFolder]);

    const relativePathStub = sinon
      .stub(vscode.workspace, "asRelativePath")
      .callsFake((uri) =>
        path.relative(workspacePath, (uri as vscode.Uri).fsPath),
      );

    await controller.testController.resolveHandler!(undefined);
    workspacesStub.restore();
    relativePathStub.restore();

    const collection = controller.testController.items;

    const testDir = collection.get(
      vscode.Uri.joinPath(workspaceUri, "test").toString(),
    );
    assert.ok(testDir);

    const serverTest = testDir!.children.get(
      vscode.Uri.joinPath(workspaceUri, "test", "server_test.rb").toString(),
    );
    assert.ok(serverTest);
  });

  test("makes the workspaces the top level when there's more than one", async () => {
    const stub = sinon.stub(common, "featureEnabled").returns(true);
    const controller = new TestController(
      context,
      FAKE_TELEMETRY,
      () => undefined,
    );
    stub.restore();

    const secondWorkspacePath = fs.mkdtempSync(
      path.join(os.tmpdir(), "ruby-lsp-test-controller-"),
    );
    const secondWorkspaceUri = vscode.Uri.file(secondWorkspacePath);

    fs.mkdirSync(path.join(secondWorkspaceUri.fsPath, "test"));
    fs.writeFileSync(
      path.join(secondWorkspaceUri.fsPath, "test", "other_test.rb"),
      "require 'test_helper'\n\nclass OtherTest < Minitest::Test; end",
    );

    const secondWorkspaceFolder: vscode.WorkspaceFolder = {
      uri: secondWorkspaceUri,
      name: "second_workspace",
      index: 1,
    };
    const workspacesStub = sinon
      .stub(vscode.workspace, "workspaceFolders")
      .get(() => [workspaceFolder, secondWorkspaceFolder]);

    const relativePathStub = sinon
      .stub(vscode.workspace, "asRelativePath")
      .callsFake((uri) => {
        const filePath = (uri as vscode.Uri).fsPath;

        if (path.basename(filePath) === "other_test.rb") {
          return path.relative(secondWorkspacePath, filePath);
        } else {
          return path.relative(workspacePath, filePath);
        }
      });

    const getWorkspaceStub = sinon
      .stub(vscode.workspace, "getWorkspaceFolder")
      .callsFake((uri) => {
        if (uri === secondWorkspaceUri) {
          return secondWorkspaceFolder;
        } else {
          return workspaceFolder;
        }
      });

    await controller.testController.resolveHandler!(undefined);

    const collection = controller.testController.items;

    // First workspace
    const workspaceItem = collection.get(workspaceUri.toString());
    assert.ok(workspaceItem);
    await controller.testController.resolveHandler!(workspaceItem);

    const testDir = workspaceItem!.children.get(
      vscode.Uri.joinPath(workspaceUri, "test").toString(),
    );
    assert.ok(testDir);

    const serverTest = testDir!.children.get(
      vscode.Uri.joinPath(workspaceUri, "test", "server_test.rb").toString(),
    );
    assert.ok(serverTest);

    // Second workspace
    const secondWorkspaceItem = collection.get(secondWorkspaceUri.toString());
    assert.ok(secondWorkspaceItem);
    await controller.testController.resolveHandler!(secondWorkspaceItem);

    const secondTestDir = secondWorkspaceItem!.children.get(
      vscode.Uri.joinPath(secondWorkspaceUri, "test").toString(),
    );
    assert.ok(secondTestDir);

    const otherTest = secondTestDir!.children.get(
      vscode.Uri.joinPath(
        secondWorkspaceUri,
        "test",
        "other_test.rb",
      ).toString(),
    );
    assert.ok(otherTest);
    workspacesStub.restore();
    relativePathStub.restore();
    getWorkspaceStub.restore();
  });
});
