import * as assert from "assert";
import path from "path";
import fs from "fs";
import os from "os";

import * as vscode from "vscode";
import { CodeLens } from "vscode-languageclient/node";
import { afterEach, beforeEach } from "mocha";
import sinon from "sinon";

import { TestController } from "../../testController";
import * as common from "../../common";
import { Workspace } from "../../workspace";
import { ManagerIdentifier } from "../../ruby";
import { Debugger } from "../../debugger";

import { FAKE_TELEMETRY } from "./fakeTelemetry";
import {
  createRubySymlinks,
  CONTEXT,
  LSP_WORKSPACE_FOLDER,
  LSP_WORKSPACE_PATH,
  LSP_WORKSPACE_URI,
} from "./helpers";

suite("TestController", () => {
  let workspace: Workspace;
  let sandbox: sinon.SinonSandbox;
  let workspaceStubs: sinon.SinonStub[];
  let controller: TestController;
  const testDirUri = vscode.Uri.joinPath(LSP_WORKSPACE_URI, "test");
  const serverTestUri = vscode.Uri.joinPath(testDirUri, "server_test.rb");
  const storeTestUri = vscode.Uri.joinPath(testDirUri, "store_test.rb");

  beforeEach(() => {
    sandbox = sinon.createSandbox();
    workspaceStubs = [];

    workspace = new Workspace(
      CONTEXT,
      LSP_WORKSPACE_FOLDER,
      FAKE_TELEMETRY,
      () => undefined,
      new Map(),
      true,
    );

    const commonStub = sandbox.stub(common, "featureEnabled").returns(true);
    controller = new TestController(
      CONTEXT,
      FAKE_TELEMETRY,
      () => undefined,
      () => Promise.resolve(workspace),
    );
    commonStub.restore();

    setupLspClientStub(workspace);
    stubWorkspaceOperations(LSP_WORKSPACE_FOLDER);
  });

  afterEach(() => {
    sandbox.restore();
    CONTEXT.subscriptions.forEach((subscription) => subscription.dispose());
  });

  function setupLspClientStub(workspace: Workspace) {
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
        {
          id: "OtherServerTest",
          uri: serverTestUri.toString(),
          label: "OtherServerTest",
          range: {
            start: { line: 0, character: 0 },
            end: { line: 12, character: 10 },
          },
          tags: ["framework:minitest"],
          children: [
            {
              id: "OtherServerTest#test_other_thing",
              uri: serverTestUri.toString(),
              label: "test_other_thing",
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
      initializeResult: {
        capabilities: {
          experimental: {
            // eslint-disable-next-line @typescript-eslint/naming-convention
            full_test_discovery: true,
          },
        },
      },
    };

    workspace.lspClient = {} as any;
    sandbox.stub(workspace, "lspClient").value(fakeClient);
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
    workspaceStubs.forEach((stub) => stub.restore());
    workspaceStubs = [];

    workspaceStubs.push(
      sandbox.stub(vscode.workspace, "workspaceFolders").get(() => workspaces),
    );

    workspaceStubs.push(
      sandbox.stub(vscode.workspace, "asRelativePath").callsFake((uri) => {
        const filePath = (uri as vscode.Uri).fsPath;

        const correctWorkspace = workspaces.find((workspace) => {
          return filePath.startsWith(workspace.uri.fsPath);
        })!;

        return path.relative(correctWorkspace.uri.fsPath, filePath);
      }),
    );

    workspaceStubs.push(
      sandbox.stub(vscode.workspace, "getWorkspaceFolder").callsFake((uri) => {
        return workspaces.find((workspace) => workspace.uri === uri);
      }),
    );
  }

  test("createTestItems doesn't break when there's a missing group", () => {
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
    const firstWorkspace = createWorkspaceWithTestFile();
    const secondWorkspace = createWorkspaceWithTestFile();

    stubWorkspaceOperations(
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
      initializeResult: {
        capabilities: {
          experimental: {
            // eslint-disable-next-line @typescript-eslint/naming-convention
            full_test_discovery: true,
          },
        },
      },
    };
    sandbox.stub(workspace, "lspClient").value(fakeClient);

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
  });

  test("takes inclusions and exclusions into account", async () => {
    await controller.testController.resolveHandler!(undefined);

    const collection = controller.testController.items;
    const testDir = collection.get(testDirUri.toString())!;
    const serverTest = testDir.children.get(serverTestUri.toString())!;
    const storeTest = testDir.children.get(storeTestUri.toString())!;
    await controller.testController.resolveHandler!(serverTest);

    const fakeClient = {
      discoverTests: sinon.stub().resolves([
        {
          id: "StoreTest",
          uri: storeTestUri.toString(),
          label: "StoreTest",
          range: {
            start: { line: 0, character: 0 },
            end: { line: 30, character: 3 },
          },
          tags: ["framework:minitest"],
          children: [
            {
              id: "StoreTest#test_store",
              uri: storeTestUri.toString(),
              label: "test_store",
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
      initializeResult: {
        capabilities: {
          experimental: {
            // eslint-disable-next-line @typescript-eslint/naming-convention
            full_test_discovery: true,
          },
        },
      },
    };

    sandbox.stub(workspace, "lspClient").value(fakeClient);
    await controller.testController.resolveHandler!(storeTest);

    const excludedExample = await controller.findTestItem(
      "StoreTest#test_store",
      storeTestUri,
    );
    assert.ok(excludedExample);

    const filteredItems = controller.buildRequestTestItems(
      [serverTest, storeTest],
      [excludedExample],
    );

    assert.strictEqual(filteredItems.length, 1);
    assert.strictEqual(filteredItems[0].id, serverTest.id);
    assert.strictEqual(filteredItems[0].children.length, 0);
  });

  test("only includes test file item if none of the children are excluded", async () => {
    await controller.testController.resolveHandler!(undefined);

    const collection = controller.testController.items;
    const testDir = collection.get(testDirUri.toString());
    assert.ok(testDir);
    const serverTest = testDir!.children.get(serverTestUri.toString())!;
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
    assert.strictEqual(serverTest.children.size, 2);
  });

  test("only includes test group item if none of the children are excluded", async () => {
    await controller.testController.resolveHandler!(undefined);

    const collection = controller.testController.items;
    const testDir = collection.get(testDirUri.toString());
    const serverTest = testDir!.children.get(serverTestUri.toString())!;
    await controller.testController.resolveHandler!(serverTest);

    // Excluding the only example inside `OtherServerTest` must result in the entire group being excluded and only
    // including the entire group of `ServerTest` because none of its children were excluded
    const excludedExample = serverTest.children
      .get("OtherServerTest")!
      .children.get("OtherServerTest#test_other_thing")!;
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
  });

  test("find test items recursively searches children based on URI and ID", async () => {
    await controller.testController.resolveHandler!(undefined);
    const collection = controller.testController.items;
    const testDir = collection.get(testDirUri.toString());
    assert.ok(testDir);
    const serverTest = testDir.children.get(serverTestUri.toString());
    assert.ok(serverTest);

    await controller.testController.resolveHandler!(serverTest);

    const group = serverTest.children.get("ServerTest");
    assert.ok(group);

    const nestedGroup = group.children.get("ServerTest::NestedTest");
    assert.ok(nestedGroup);

    const example = nestedGroup.children.get(
      "ServerTest::NestedTest#test_something",
    );
    assert.ok(example);

    assert.strictEqual(
      group,
      await controller.findTestItem(group.id, group.uri!),
    );
    assert.strictEqual(
      example,
      await controller.findTestItem(example.id, example.uri!),
    );
  });

  test("find test items based on URI and ID when nested groups exist", async () => {
    await controller.testController.resolveHandler!(undefined);

    assert.strictEqual(
      "ServerTest",
      (await controller.findTestItem("ServerTest", serverTestUri))!.id,
    );
    assert.strictEqual(
      "ServerTest::NestedTest",
      (await controller.findTestItem("ServerTest::NestedTest", serverTestUri))!
        .id,
    );
    assert.strictEqual(
      "ServerTest::NestedTest#test_something",
      (await controller.findTestItem(
        "ServerTest::NestedTest#test_something",
        serverTestUri,
      ))!.id,
    );
  });

  test("finding an item inside a test file that was never expanded automatically discovers children", async () => {
    await controller.testController.resolveHandler!(undefined);
    const collection = controller.testController.items;
    const testDir = collection.get(testDirUri.toString());
    assert.ok(testDir);

    const serverTest = testDir.children.get(serverTestUri.toString());
    assert.ok(serverTest);

    // The main explorer solution now auto-resolves at least one test file inside of each test dir. Here, we force the
    // children to be empty so that this test is deterministic
    serverTest.children.replace([]);

    await controller.findTestItem("ServerTest", serverTestUri);
    assert.ok(serverTest.children.size > 0);
  });

  test("running a test", async () => {
    await controller.testController.resolveHandler!(undefined);

    const testItem = (await controller.findTestItem(
      "ServerTest::NestedTest#test_something",
      serverTestUri,
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

    sandbox.stub(workspace, "lspClient").value({
      resolveTestCommands: sinon.stub().resolves({
        commands: [`node ${fakeServerPath}`],
        reporterPath: undefined,
      }),
      initializeResult: {
        capabilities: {
          experimental: {
            // eslint-disable-next-line @typescript-eslint/naming-convention
            full_test_discovery: true,
          },
        },
      },
    });

    const cancellationSource = new vscode.CancellationTokenSource();
    const runStub = {
      started: sinon.stub(),
      passed: sinon.stub(),
      enqueued: sinon.stub(),
      end: sinon.stub(),
      token: cancellationSource.token,
      appendOutput: sinon.stub(),
    } as any;
    sandbox.stub(controller.testController, "createTestRun").returns(runStub);

    const runRequest = new vscode.TestRunRequest([testItem]);
    await controller.runTest(runRequest, cancellationSource.token);

    assert.ok(runStub.enqueued.calledWith(testItem));
    assert.ok(runStub.started.calledWith(testItem));
    assert.ok(runStub.passed.calledWith(testItem));
    assert.ok(runStub.end.calledWithExactly());
  }).timeout(10000);

  test("debugging a test", async () => {
    await controller.testController.resolveHandler!(undefined);

    const manager =
      os.platform() === "win32"
        ? { identifier: ManagerIdentifier.None }
        : { identifier: ManagerIdentifier.Chruby };

    // eslint-disable-next-line no-process-env
    if (process.env.CI) {
      createRubySymlinks();
    }

    await workspace.ruby.activateRuby(manager);

    const testItem = (await controller.findTestItem(
      "ServerTest::NestedTest#test_something",
      serverTestUri,
    ))!;

    const program = `bundle exec ruby -Itest ${path.join("test", "fixtures", "minitest_example.rb")}`;

    sandbox.stub(workspace, "lspClient").value({
      resolveTestCommands: sinon.stub().resolves({
        commands: [program],
        reporterPaths: [
          path.join(
            LSP_WORKSPACE_PATH,
            "lib",
            "ruby_lsp",
            "test_reporters",
            "minitest_reporter.rb",
          ),
        ],
      }),
      initializeResult: {
        capabilities: {
          experimental: {
            // eslint-disable-next-line @typescript-eslint/naming-convention
            full_test_discovery: true,
          },
        },
      },
    });

    const cancellationSource = new vscode.CancellationTokenSource();
    const runStub = {
      started: sinon.stub(),
      passed: sinon.stub(),
      enqueued: sinon.stub(),
      end: sinon.stub(),
      token: cancellationSource.token,
      appendOutput: sinon.stub(),
    } as any;
    sandbox.stub(controller.testController, "createTestRun").returns(runStub);

    const debug = new Debugger(CONTEXT, () => workspace);
    const startDebuggingSpy = sandbox.spy(vscode.debug, "startDebugging");

    const runRequest = new vscode.TestRunRequest(
      [testItem],
      [],
      controller.testDebugProfile,
    );
    await controller.runTest(runRequest, cancellationSource.token);

    assert.ok(runStub.end.calledWithExactly());
    assert.ok(
      startDebuggingSpy.calledOnceWith(
        LSP_WORKSPACE_FOLDER,
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

    debug.dispose();
  }).timeout(10000);

  test("running a test with the coverage profile", async () => {
    await controller.testController.resolveHandler!(undefined);

    const testItem = (await controller.findTestItem(
      "ServerTest::NestedTest#test_something",
      serverTestUri,
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
    sandbox.stub(workspace, "lspClient").value({
      resolveTestCommands: sinon.stub().resolves({
        commands: [`node ${fakeServerPath}`],
        reporterPath: undefined,
      }),
      initializeResult: {
        capabilities: {
          experimental: {
            // eslint-disable-next-line @typescript-eslint/naming-convention
            full_test_discovery: true,
          },
        },
      },
    });

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
    sandbox.stub(controller.testController, "createTestRun").returns(runStub);

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

    sandbox.stub(vscode.workspace, "fs").get(() => {
      return {
        readFile: sinon.stub().resolves(fakeFileContents),
        stat: sinon.stub().resolves({ type: vscode.FileType.File }),
      };
    });
    await controller.runTest(runRequest, cancellationSource.token);

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
  }).timeout(10000);
});
