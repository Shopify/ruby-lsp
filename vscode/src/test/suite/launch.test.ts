import assert from "assert";
import path from "path";

import * as vscode from "vscode";
import { State } from "vscode-languageclient/node";
import sinon from "sinon";
import { afterEach, beforeEach } from "mocha";

import { ManagerIdentifier, Ruby } from "../../ruby";
import Client from "../../client";
import { WorkspaceChannel } from "../../workspaceChannel";
import * as common from "../../common";

import { FAKE_TELEMETRY, FakeLogger } from "./fakeTelemetry";
import { createContext, createRubySymlinks, FakeContext } from "./helpers";

suite("Launch integrations", () => {
  const workspacePath = path.dirname(path.dirname(path.dirname(path.dirname(__dirname))));
  const workspaceUri = vscode.Uri.file(workspacePath);
  const workspaceFolder: vscode.WorkspaceFolder = {
    uri: workspaceUri,
    name: path.basename(workspaceUri.fsPath),
    index: 0,
  };

  let context: FakeContext;
  let sandbox: sinon.SinonSandbox;

  beforeEach(() => {
    sandbox = sinon.createSandbox();
    context = createContext();
  });

  afterEach(() => {
    sandbox.restore();
    context.dispose();
  });

  const fakeLogger = new FakeLogger();
  const outputChannel = new WorkspaceChannel("fake", fakeLogger as any);

  async function createClient() {
    const ruby = new Ruby(context, workspaceFolder, outputChannel, FAKE_TELEMETRY);

    if (process.env.CI && common.isWindows()) {
      await ruby.activateRuby({ identifier: ManagerIdentifier.RubyInstaller });
    } else if (process.env.CI) {
      await ruby.activateRuby({ identifier: ManagerIdentifier.Chruby });
    } else {
      await ruby.activateRuby();
    }

    const client = new Client(
      context,
      FAKE_TELEMETRY,
      ruby,
      () => {},
      workspaceFolder,
      outputChannel,
      new Map<string, string>(),
    );

    client.clientOptions.initializationFailedHandler = (error) => {
      assert.fail(`Failed to start server ${error.message}\n${fakeLogger.receivedMessages}`);
    };

    return client;
  }

  async function startClient(client: Client): Promise<void> {
    try {
      await client.start();
    } catch (error: any) {
      assert.fail(`Failed to start server ${error.message}\n${fakeLogger.receivedMessages}`);
    }
    assert.strictEqual(client.state, State.Running);

    // Wait for composing the bundle and indexing to finish. We don't _need_ the codebase to be indexed for these tests,
    // but trying to stop the server in the middle of composing the bundle may time out, so this makes the tests more
    // robust
    await client.waitForIndexing();
  }

  beforeEach(() => {
    if (process.env.CI) {
      createRubySymlinks();
    }
  });

  test("with launcher mode enabled", async () => {
    sandbox.stub(common, "featureEnabled").returns(true);
    const client = await createClient();

    await startClient(client);

    try {
      await client.stop();
      await client.dispose();
    } catch (error: any) {
      assert.fail(`Failed to stop server: ${error.message}\n${fakeLogger.receivedMessages}`);
    }
  }).timeout(120000);
});
