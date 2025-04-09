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
import { Workspace } from "../../workspace";
import { ManagerIdentifier } from "../../ruby";
import { Debugger } from "../../debugger";

import { FAKE_TELEMETRY } from "./fakeTelemetry";
import { createRubySymlinks } from "./helpers";

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
    extensionUri: vscode.Uri.joinPath(workspaceUri, "vscode"),
  } as unknown as vscode.ExtensionContext;
  const workspace = new Workspace(
    context,
    workspaceFolder,
    FAKE_TELEMETRY,
    () => undefined,
    new Map(),
    true,
  );

  function createController() {
    const commonStub = sinon.stub(common, "featureEnabled").returns(true);
    const controller = new TestController(
      context,
      FAKE_TELEMETRY,
      () => undefined,
      () => Promise.resolve(workspace),
    );
    commonStub.restore();
    return controller;
  }

  afterEach(() => {
    context.subscriptions.forEach((subscription) => subscription.dispose());
  });

  async function withController(
    callback: (controller: TestController) => Promise<void>,
  ) {
    const workspacesStub = sinon
      .stub(vscode.workspace, "workspaceFolders")
      .get(() => [workspaceFolder]);

    const relativePathStub = sinon
      .stub(vscode.workspace, "asRelativePath")
      .callsFake((uri) =>
        path.relative(workspacePath, (uri as vscode.Uri).fsPath),
      );

    const controller = createController();
    const testDirUri = vscode.Uri.joinPath(workspaceUri, "test");
    const serverTestUri = vscode.Uri.joinPath(
      workspaceUri,
      "test",
      "server_test.rb",
    );
    const fakeClient = {
      discoverTests: sinon.stub().resolves([
        {
          id: "ServerTest",
          uri: serverTestUri.toString(),
          label: "ServerTest",
          range: {
            start: { line: 0, character: 0 },
            end: { line: 12, character: 10 },
          },
          tags: ["framework:minitest"],
          children: [
            {
              id: "ServerTest::NestedTest",
              uri: serverTestUri.toString(),
              label: "NestedTest",
              range: {
                start: { line: 2, character: 0 },
                end: { line: 10, character: 10 },
              },
              tags: ["framework:minitest"],
              children: [
                {
                  id: "ServerTest::NestedTest#test_something",
                  uri: serverTestUri.toString(),
                  label: "test_something",
                  range: {
                    start: { line: 2, character: 0 },
                    end: { line: 10, character: 10 },
                  },
                  tags: ["framework:minitest"],
                  children: [],
                },
              ],
            },
          ],
        },
      ]),
      waitForIndexing: sinon.stub().resolves(),
    };
    workspace.lspClient = fakeClient as any;
    await controller.testController.resolveHandler!(undefined);
    const collection = controller.testController.items;
    const testDir = collection.get(testDirUri.toString());
    assert.ok(testDir);

    const serverTest = testDir.children.get(serverTestUri.toString());
    assert.ok(serverTest);

    await controller.testController.resolveHandler!(serverTest);
    assert.ok(fakeClient.discoverTests.called);

    const group = serverTest.children.get("ServerTest");
    assert.ok(group);

    const nestedGroup = group.children.get("ServerTest::NestedTest");
    assert.ok(nestedGroup);

    const example = nestedGroup.children.get(
      "ServerTest::NestedTest#test_something",
    );
    assert.ok(example);

    await callback(controller);

    workspacesStub.restore();
    relativePathStub.restore();
  }

  async function assertTags(
    itemId: string,
    itemUri: vscode.Uri,
    controller: TestController,
    tags: string[],
  ) {
    const item = await controller.findTestItem(itemId, itemUri);
    assert.ok(item);
    assert.deepStrictEqual(
      item!.tags.map((tag) => tag.id),
      tags,
    );
  }

  function createWorkspaceWithTestFile() {
    const workspacePath = fs.mkdtempSync(
      path.join(os.tmpdir(), "ruby-lsp-test-controller-"),
    );
    const workspaceUri = vscode.Uri.file(workspacePath);

    fs.mkdirSync(path.join(workspaceUri.fsPath, "test"));
    const testFilePath = path.join(workspaceUri.fsPath, "test", "foo_test.rb");
    fs.writeFileSync(
      testFilePath,
      "require 'test_helper'\n\nclass FooTest < Minitest::Test; def test_foo; end; end",
    );

    const workspaceFolder: vscode.WorkspaceFolder = {
      uri: workspaceUri,
      name: path.basename(workspacePath),
      index: 1,
    };

    return { workspaceFolder, testFileUri: vscode.Uri.file(testFilePath) };
  }

  function stubWorkspaceOperations(...workspaces: vscode.WorkspaceFolder[]) {
    const stubs = [];
    stubs.push(
      sinon.stub(vscode.workspace, "workspaceFolders").get(() => workspaces),
    );

    stubs.push(
      sinon.stub(vscode.workspace, "asRelativePath").callsFake((uri) => {
        const filePath = (uri as vscode.Uri).fsPath;

        const correctWorkspace = workspaces.find((workspace) => {
          return filePath.startsWith(workspace.uri.fsPath);
        })!;

        return path.relative(correctWorkspace.uri.fsPath, filePath);
      }),
    );

    stubs.push(
      sinon.stub(vscode.workspace, "getWorkspaceFolder").callsFake((uri) => {
        return workspaces.find((workspace) => workspace.uri === uri);
      }),
    );

    return stubs;
  }

  test("createTestItems doesn't break when there's a missing group", () => {
    const controller = createController();
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

  test("makes the workspaces the top level when there's more than one", async () => {
    const controller = createController();
    const firstWorkspace = createWorkspaceWithTestFile();
    const secondWorkspace = createWorkspaceWithTestFile();

    const stubs = stubWorkspaceOperations(
      firstWorkspace.workspaceFolder,
      secondWorkspace.workspaceFolder,
    );

    await controller.testController.resolveHandler!(undefined);

    const collection = controller.testController.items;

    // First workspace
    const workspaceItem = collection.get(
      firstWorkspace.workspaceFolder.uri.toString(),
    );
    assert.ok(workspaceItem);
    assert.deepStrictEqual(
      workspaceItem!.tags.map((tag) => tag.id),
      ["workspace", "debug"],
    );

    const fakeClient = {
      discoverTests: (fileUri: vscode.Uri) => {
        let uri;
        if (
          fileUri.fsPath.startsWith(firstWorkspace.workspaceFolder.uri.fsPath)
        ) {
          uri = firstWorkspace.testFileUri.toString();
        } else {
          uri = secondWorkspace.testFileUri.toString();
        }

        return [
          {
            id: "FooTest",
            uri,
            label: "FooTest",
            range: {
              start: { line: 0, character: 0 },
              end: { line: 12, character: 10 },
            },
            tags: ["framework:minitest"],
            children: [
              {
                id: "FooTest::NestedTest",
                uri,
                label: "NestedTest",
                range: {
                  start: { line: 2, character: 0 },
                  end: { line: 10, character: 10 },
                },
                tags: ["framework:minitest"],
                children: [
                  {
                    id: "FooTest::NestedTest#test_something",
                    uri,
                    label: "test_something",
                    range: {
                      start: { line: 2, character: 0 },
                      end: { line: 10, character: 10 },
                    },
                    tags: ["framework:minitest"],
                    children: [],
                  },
                ],
              },
            ],
          },
        ];
      },
      waitForIndexing: sinon.stub().resolves(),
    };
    workspace.lspClient = fakeClient as any;

    await controller.testController.resolveHandler!(workspaceItem);

    const testDir = workspaceItem!.children.get(
      vscode.Uri.joinPath(
        firstWorkspace.workspaceFolder.uri,
        "test",
      ).toString(),
    );
    assert.ok(testDir);
    assert.deepStrictEqual(
      testDir!.tags.map((tag) => tag.id),
      ["test_dir", "debug", "framework:minitest"],
    );

    const firstWorkspaceTest = testDir!.children.get(
      firstWorkspace.testFileUri.toString(),
    );
    assert.ok(firstWorkspaceTest);
    assert.deepStrictEqual(
      firstWorkspaceTest!.tags.map((tag) => tag.id),
      ["test_file", "debug", "framework:minitest"],
    );

    // Second workspace
    const secondWorkspaceItem = collection.get(
      secondWorkspace.workspaceFolder.uri.toString(),
    );
    assert.ok(secondWorkspaceItem);
    assert.deepStrictEqual(
      secondWorkspaceItem!.tags.map((tag) => tag.id),
      ["workspace", "debug"],
    );

    await controller.testController.resolveHandler!(secondWorkspaceItem);

    const secondTestDir = secondWorkspaceItem!.children.get(
      vscode.Uri.joinPath(
        secondWorkspace.workspaceFolder.uri,
        "test",
      ).toString(),
    );
    assert.ok(secondTestDir);
    assert.deepStrictEqual(
      secondTestDir!.tags.map((tag) => tag.id),
      ["test_dir", "debug", "framework:minitest"],
    );

    const otherTest = secondTestDir!.children.get(
      secondWorkspace.testFileUri.toString(),
    );
    assert.ok(otherTest);
    assert.deepStrictEqual(
      otherTest!.tags.map((tag) => tag.id),
      ["test_file", "debug", "framework:minitest"],
    );

    stubs.forEach((stub) => stub.restore());
  });

  test("takes inclusions and exclusions into account", async () => {
    const controller = createController();
    const stubs = stubWorkspaceOperations(workspaceFolder);
    await controller.testController.resolveHandler!(undefined);

    const collection = controller.testController.items;
    const testDir = collection.get(
      vscode.Uri.joinPath(workspaceUri, "test").toString(),
    );
    const serverTest = testDir!.children.get(
      vscode.Uri.joinPath(workspaceUri, "test", "server_test.rb").toString(),
    )!;
    const storeTest = testDir!.children.get(
      vscode.Uri.joinPath(workspaceUri, "test", "store_test.rb").toString(),
    )!;
    let fakeClient = {
      discoverTests: sinon.stub().resolves([
        {
          id: "ServerTest",
          uri: "file:///test/server_test.rb",
          label: "ServerTest",
          range: {
            start: { line: 0, character: 0 },
            end: { line: 30, character: 3 },
          },
          tags: ["framework:minitest"],
          children: [
            {
              id: "ServerTest#test_server",
              uri: "file:///test/server_test.rb",
              label: "test_server",
              range: {
                start: { line: 1, character: 2 },
                end: { line: 10, character: 3 },
              },
              tags: ["framework:minitest"],
              children: [],
            },
          ],
        },
      ]),
      waitForIndexing: sinon.stub().resolves(),
    };

    workspace.lspClient = fakeClient as any;
    await controller.testController.resolveHandler!(serverTest);

    fakeClient = {
      discoverTests: sinon.stub().resolves([
        {
          id: "StoreTest",
          uri: "file:///test/store_test.rb",
          label: "StoreTest",
          range: {
            start: { line: 0, character: 0 },
            end: { line: 30, character: 3 },
          },
          tags: ["framework:minitest"],
          children: [
            {
              id: "StoreTest#test_store",
              uri: "file:///test/store_test.rb",
              label: "test_store",
              range: {
                start: { line: 1, character: 2 },
                end: { line: 10, character: 3 },
              },
              tags: ["framework:minitest"],
              children: [],
            },
            {
              id: "StoreTest#test_other_store",
              uri: "file:///test/store_test.rb",
              label: "test_other_store",
              range: {
                start: { line: 20, character: 2 },
                end: { line: 30, character: 3 },
              },
              tags: ["framework:minitest"],
              children: [],
            },
          ],
        },
      ]),
      waitForIndexing: sinon.stub().resolves(),
    };

    workspace.lspClient = fakeClient as any;
    await controller.testController.resolveHandler!(storeTest);

    const excludedExample = serverTest.children
      .get("ServerTest")!
      .children.get("ServerTest#test_server")!;
    assert.ok(excludedExample);

    const filteredItems = controller.buildRequestTestItems(
      [serverTest, storeTest],
      [excludedExample],
    );

    assert.strictEqual(filteredItems.length, 1);
    assert.strictEqual(filteredItems[0].id, storeTest.id);
    assert.strictEqual(filteredItems[0].children.length, 0);

    stubs.forEach((stub) => stub.restore());
  });

  test("only includes test file item if none of the children are excluded", async () => {
    const controller = createController();
    const stubs = stubWorkspaceOperations(workspaceFolder);
    const fakeClient = {
      discoverTests: sinon.stub().resolves([
        {
          id: "ServerTest",
          uri: "file:///test/server_test.rb",
          label: "ServerTest",
          range: {
            start: { line: 0, character: 0 },
            end: { line: 30, character: 3 },
          },
          tags: ["framework:minitest"],
          children: [
            {
              id: "ServerTest#test_server",
              uri: "file:///test/server_test.rb",
              label: "test_server",
              range: {
                start: { line: 1, character: 2 },
                end: { line: 10, character: 3 },
              },
              tags: ["framework:minitest"],
              children: [],
            },
          ],
        },
      ]),
      waitForIndexing: sinon.stub().resolves(),
    };

    workspace.lspClient = fakeClient as any;

    await controller.testController.resolveHandler!(undefined);

    const collection = controller.testController.items;
    const testDir = collection.get(
      vscode.Uri.joinPath(workspaceUri, "test").toString(),
    );
    assert.ok(testDir);
    const serverTest = testDir!.children.get(
      vscode.Uri.joinPath(workspaceUri, "test", "server_test.rb").toString(),
    )!;
    await controller.testController.resolveHandler!(serverTest);

    await assertTags(testDir.uri!.toString(), testDir.uri!, controller, [
      "test_dir",
      "debug",
      "framework:minitest",
    ]);
    await assertTags(serverTest.uri!.toString(), serverTest.uri!, controller, [
      "test_file",
      "debug",
      "framework:minitest",
    ]);

    const filteredItems = controller.buildRequestTestItems([serverTest], []);

    assert.strictEqual(filteredItems.length, 1);
    assert.strictEqual(filteredItems[0].id, serverTest.id);
    // No children are present because they are all included and therefore we can simply execute the entire test file in
    // one go
    assert.strictEqual(filteredItems[0].children.length, 0);
    // However, the original item should not be mutated or else it will mess up the explorer tree structure
    assert.strictEqual(serverTest.children.size, 1);

    stubs.forEach((stub) => stub.restore());
  });

  test("only includes test group item if none of the children are excluded", async () => {
    const controller = createController();
    const stubs = stubWorkspaceOperations(workspaceFolder);
    await controller.testController.resolveHandler!(undefined);

    const collection = controller.testController.items;
    const testDir = collection.get(
      vscode.Uri.joinPath(workspaceUri, "test").toString(),
    );
    const serverTest = testDir!.children.get(
      vscode.Uri.joinPath(workspaceUri, "test", "server_test.rb").toString(),
    )!;
    const fakeClient = {
      discoverTests: sinon.stub().resolves([
        {
          id: "ServerTest",
          uri: "file:///test/server_test.rb",
          label: "ServerTest",
          range: {
            start: { line: 0, character: 0 },
            end: { line: 30, character: 3 },
          },
          tags: ["framework:minitest"],
          children: [
            {
              id: "ServerTest#test_server",
              uri: "file:///test/server_test.rb",
              label: "test_server",
              range: {
                start: { line: 1, character: 2 },
                end: { line: 10, character: 3 },
              },
              tags: ["framework:minitest"],
              children: [],
            },
          ],
        },
        {
          id: "OtherServerTest",
          uri: "file:///test/server_test.rb",
          label: "OtherServerTest",
          range: {
            start: { line: 32, character: 0 },
            end: { line: 60, character: 3 },
          },
          tags: ["framework:minitest"],
          children: [
            {
              id: "OtherServerTest#test_other_server",
              uri: "file:///test/server_test.rb",
              label: "test_server",
              range: {
                start: { line: 33, character: 2 },
                end: { line: 58, character: 3 },
              },
              tags: ["framework:minitest"],
              children: [],
            },
          ],
        },
      ]),
      waitForIndexing: sinon.stub().resolves(),
    };

    workspace.lspClient = fakeClient as any;
    await controller.testController.resolveHandler!(serverTest);

    // Excluding the only example inside `OtherServerTest` must result in the entire group being excluded and only
    // including the entire group of `ServerTest` because none of its children were excluded
    const excludedExample = serverTest.children
      .get("OtherServerTest")!
      .children.get("OtherServerTest#test_other_server")!;
    assert.ok(excludedExample);

    const filteredItems = controller.buildRequestTestItems(
      [serverTest],
      [excludedExample],
    );

    assert.strictEqual(filteredItems.length, 1);
    assert.strictEqual(filteredItems[0].id, serverTest.id);
    // No children are present because they are all included and therefore we can simply execute the entire test file in
    // one go
    assert.strictEqual(filteredItems[0].children.length, 1);
    assert.strictEqual(filteredItems[0].children[0].id, "ServerTest");
    assert.strictEqual(filteredItems[0].children[0].children.length, 0);

    // However, the original item should not be mutated or else it will mess up the explorer tree structure
    assert.strictEqual(serverTest.children.get("ServerTest")!.children.size, 1);

    stubs.forEach((stub) => stub.restore());
  });

  test("find test items recursively searches children based on URI and ID", async () => {
    const controller = createController();
    const stubs = stubWorkspaceOperations(workspaceFolder);
    await controller.testController.resolveHandler!(undefined);
    const collection = controller.testController.items;
    const testDirUri = vscode.Uri.joinPath(workspaceUri, "test");
    const testDir = collection.get(testDirUri.toString());
    assert.ok(testDir);

    const serverTestUri = vscode.Uri.joinPath(
      workspaceUri,
      "test",
      "server_test.rb",
    );
    const serverTest = testDir.children.get(serverTestUri.toString());
    assert.ok(serverTest);

    const fakeClient = {
      discoverTests: sinon.stub().resolves([
        {
          id: "ServerTest",
          uri: serverTestUri.toString(),
          label: "ServerTest",
          range: {
            start: { line: 0, character: 0 },
            end: { line: 12, character: 10 },
          },
          tags: ["framework:minitest"],
          children: [
            {
              id: "ServerTest#test_something",
              uri: serverTestUri.toString(),
              label: "test_something",
              range: {
                start: { line: 2, character: 0 },
                end: { line: 10, character: 10 },
              },
              tags: ["framework:minitest"],
              children: [],
            },
          ],
        },
      ]),
      waitForIndexing: sinon.stub().resolves(),
    };
    workspace.lspClient = fakeClient as any;
    await controller.testController.resolveHandler!(serverTest);
    assert.strictEqual(fakeClient.discoverTests.callCount, 1);

    const group = serverTest.children.get("ServerTest");
    assert.ok(group);

    const example = group.children.get("ServerTest#test_something");
    assert.ok(example);

    assert.strictEqual(
      group,
      await controller.findTestItem(group.id, group.uri!),
    );
    assert.strictEqual(
      example,
      await controller.findTestItem(example.id, example.uri!),
    );

    stubs.forEach((stub) => stub.restore());
  });

  test("find test items based on URI and ID when nested groups exist", async () => {
    await withController(async (controller) => {
      const uri = vscode.Uri.joinPath(workspaceUri, "test", "server_test.rb");
      assert.strictEqual(
        "ServerTest",
        (await controller.findTestItem("ServerTest", uri))!.id,
      );
      assert.strictEqual(
        "ServerTest::NestedTest",
        (await controller.findTestItem("ServerTest::NestedTest", uri))!.id,
      );
      assert.strictEqual(
        "ServerTest::NestedTest#test_something",
        (await controller.findTestItem(
          "ServerTest::NestedTest#test_something",
          uri,
        ))!.id,
      );
    });
  });

  test("finding an item inside a test file that was never expanded automatically discovers children", async () => {
    const controller = createController();
    const stubs = stubWorkspaceOperations(workspaceFolder);
    const serverTestUri = vscode.Uri.joinPath(
      workspaceUri,
      "test",
      "server_test.rb",
    );

    const fakeClient = {
      discoverTests: sinon.stub().resolves([
        {
          id: "ServerTest",
          uri: serverTestUri.toString(),
          label: "ServerTest",
          range: {
            start: { line: 0, character: 0 },
            end: { line: 12, character: 10 },
          },
          tags: ["framework:minitest"],
          children: [
            {
              id: "ServerTest::NestedTest",
              uri: serverTestUri.toString(),
              label: "NestedTest",
              range: {
                start: { line: 2, character: 0 },
                end: { line: 10, character: 10 },
              },
              tags: ["framework:minitest"],
              children: [
                {
                  id: "ServerTest::NestedTest#test_something",
                  uri: serverTestUri.toString(),
                  label: "test_something",
                  range: {
                    start: { line: 2, character: 0 },
                    end: { line: 10, character: 10 },
                  },
                  tags: ["framework:minitest"],
                  children: [],
                },
              ],
            },
          ],
        },
      ]),
      waitForIndexing: sinon.stub().resolves(),
    };
    workspace.lspClient = fakeClient as any;

    await controller.testController.resolveHandler!(undefined);
    const collection = controller.testController.items;
    const testDirUri = vscode.Uri.joinPath(workspaceUri, "test");
    const testDir = collection.get(testDirUri.toString());
    assert.ok(testDir);

    const serverTest = testDir.children.get(serverTestUri.toString());
    assert.ok(serverTest);

    // The main explorer solution now auto-resolves at least one test file inside of each test dir. Here, we force the
    // children to be empty so that this test is deterministic
    serverTest.children.replace([]);
    fakeClient.discoverTests.resetHistory();

    await controller.findTestItem("ServerTest", serverTestUri);
    assert.strictEqual(fakeClient.discoverTests.callCount, 1);

    stubs.forEach((stub) => stub.restore());
  });

  test("running a test", async () => {
    await withController(async (controller) => {
      const uri = vscode.Uri.joinPath(workspaceUri, "test", "server_test.rb");
      const testItem = (await controller.findTestItem(
        "ServerTest::NestedTest#test_something",
        uri,
      ))!;

      const fakeServerPath = path.join(
        __dirname,
        "..",
        "..",
        "..",
        "src",
        "test",
        "suite",
        "fakeTestServer.js",
      );

      // eslint-disable-next-line no-process-env
      workspace.ruby.mergeComposedEnvironment(process.env as any);

      workspace.lspClient = {
        resolveTestCommands: sinon.stub().resolves({
          commands: [`node ${fakeServerPath}`],
          reporterPath: undefined,
        }),
      } as any;

      const cancellationSource = new vscode.CancellationTokenSource();
      const runStub = {
        started: sinon.stub(),
        passed: sinon.stub(),
        enqueued: sinon.stub(),
        end: sinon.stub(),
        token: cancellationSource.token,
        appendOutput: sinon.stub(),
      } as any;
      const createRunStub = sinon
        .stub(controller.testController, "createTestRun")
        .returns(runStub);

      const runRequest = new vscode.TestRunRequest([testItem]);
      await controller.runTest(runRequest, cancellationSource.token);

      assert.ok(runStub.enqueued.calledWith(testItem));
      assert.ok(runStub.started.calledWith(testItem));
      assert.ok(runStub.passed.calledWith(testItem));
      assert.ok(runStub.end.calledWithExactly());

      createRunStub.restore();
    });
  }).timeout(10000);

  test("debugging a test", async () => {
    const manager =
      os.platform() === "win32"
        ? { identifier: ManagerIdentifier.None }
        : { identifier: ManagerIdentifier.Chruby };

    // eslint-disable-next-line no-process-env
    if (process.env.CI) {
      createRubySymlinks();
    }

    await workspace.ruby.activateRuby(manager);

    await withController(async (controller) => {
      const uri = vscode.Uri.joinPath(workspaceUri, "test", "server_test.rb");
      const testItem = (await controller.findTestItem(
        "ServerTest::NestedTest#test_something",
        uri,
      ))!;

      const program = `bundle exec ruby -Itest ${path.join("test", "fixtures", "minitest_example.rb")}`;
      workspace.lspClient = {
        resolveTestCommands: sinon.stub().resolves({
          commands: [program],
          reporterPaths: [
            path.join(
              workspacePath,
              "lib",
              "ruby_lsp",
              "ruby_lsp_reporter_plugin.rb",
            ),
          ],
        }),
      } as any;

      const cancellationSource = new vscode.CancellationTokenSource();
      const runStub = {
        started: sinon.stub(),
        passed: sinon.stub(),
        enqueued: sinon.stub(),
        end: sinon.stub(),
        token: cancellationSource.token,
        appendOutput: sinon.stub(),
      } as any;
      const createRunStub = sinon
        .stub(controller.testController, "createTestRun")
        .returns(runStub);

      const debug = new Debugger(context, () => workspace);
      const startDebuggingSpy = sinon.spy(vscode.debug, "startDebugging");

      const runRequest = new vscode.TestRunRequest(
        [testItem],
        [],
        controller.testDebugProfile,
      );
      await controller.runTest(runRequest, cancellationSource.token);

      assert.ok(runStub.end.calledWithExactly());
      assert.ok(
        startDebuggingSpy.calledOnceWith(
          workspaceFolder,
          {
            type: "ruby_lsp",
            name: "Debug",
            request: "launch",
            program,
            env: {
              ...workspace.ruby.env,
              DISABLE_SPRING: "1",
              RUBY_LSP_TEST_RUNNER: "debug",
            },
          },
          { testRun: runStub },
        ),
      );

      createRunStub.restore();
      startDebuggingSpy.restore();
      debug.dispose();
    });
  }).timeout(10000);

  test("running a test with the coverage profile", async () => {
    await withController(async (controller) => {
      const uri = vscode.Uri.joinPath(workspaceUri, "test", "server_test.rb");
      const testItem = (await controller.findTestItem(
        "ServerTest::NestedTest#test_something",
        uri,
      ))!;

      const fakeServerPath = path.join(
        __dirname,
        "..",
        "..",
        "..",
        "src",
        "test",
        "suite",
        "fakeTestServer.js",
      );

      // eslint-disable-next-line no-process-env
      workspace.ruby.mergeComposedEnvironment(process.env as any);

      workspace.lspClient = {
        resolveTestCommands: sinon.stub().resolves({
          commands: [`node ${fakeServerPath}`],
          reporterPath: undefined,
        }),
      } as any;

      const cancellationSource = new vscode.CancellationTokenSource();
      const runStub = {
        started: sinon.stub(),
        passed: sinon.stub(),
        enqueued: sinon.stub(),
        end: sinon.stub(),
        addCoverage: sinon.stub(),
        appendOutput: sinon.stub(),
        token: cancellationSource.token,
      } as any;
      const createRunStub = sinon
        .stub(controller.testController, "createTestRun")
        .returns(runStub);

      const runRequest = new vscode.TestRunRequest(
        [testItem],
        [],
        controller.coverageProfile,
      );
      const fakeFileContents = Buffer.from(
        JSON.stringify({
          // eslint-disable-next-line @typescript-eslint/naming-convention
          "file:///test/server_test.rb": [
            {
              executed: 1,
              location: { line: 0, character: 0 },
              branches: [],
            },
          ],
        }),
      );

      const fsStub = sinon.stub(vscode.workspace, "fs").get(() => {
        return {
          readFile: sinon.stub().resolves(fakeFileContents),
          stat: sinon.stub().resolves({ type: vscode.FileType.File }),
        };
      });
      await controller.runTest(runRequest, cancellationSource.token);
      fsStub.restore();

      assert.ok(runStub.enqueued.calledWith(testItem));
      assert.ok(runStub.started.calledWith(testItem));
      assert.ok(runStub.passed.calledWith(testItem));
      assert.ok(runStub.end.calledWithExactly());
      assert.ok(
        runStub.appendOutput.calledWithExactly(
          "\r\n\r\nProcessing test coverage results...\r\n\r\n",
        ),
      );
      assert.ok(runStub.addCoverage.calledOnce);

      createRunStub.restore();
    });
  }).timeout(10000);
});
