/* eslint-disable no-process-env */
import assert from "assert";
import path from "path";

import * as vscode from "vscode";
import { State, WorkDoneProgress } from "vscode-languageclient/node";
import { before } from "mocha";
import sinon from "sinon";

import { Ruby } from "../../ruby";
import Client from "../../client";
import { WorkspaceChannel } from "../../workspaceChannel";
import * as common from "../../common";

import { setupRubyForCi, FAKE_TELEMETRY, FakeLogger } from "./testHelpers";

suite("Launch integrations", () => {
  before(async () => {
    // Ensure that we're activating the correct Ruby version on CI
    if (process.env.CI) {
      await setupRubyForCi();
    }
  });

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
  const fakeLogger = new FakeLogger();
  const outputChannel = new WorkspaceChannel("fake", fakeLogger as any);

  async function createClient() {
    const ruby = new Ruby(
      context,
      workspaceFolder,
      outputChannel,
      FAKE_TELEMETRY,
    );
    await ruby.activateRuby();

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
      assert.fail(
        `Failed to start server ${error.message}\n${fakeLogger.receivedMessages}`,
      );
    };

    return client;
  }

  async function startClient(client: Client) {
    await client.start();
    // Wait for composing the bundle and indexing to finish. We don't _need_ the codebase to be indexed for these tests,
    // but trying to stop the server in the middle of composing the bundle may timeout, so this makes the tests more
    // robust
    return new Promise<Client>((resolve) => {
      client.onProgress(
        WorkDoneProgress.type,
        "indexing-progress",
        (value: any) => {
          if (value.kind === "end") {
            resolve(client);
          }
        },
      );
    });
  }

  test("with launcher mode enabled", async () => {
    const featureStub = sinon.stub(common, "featureEnabled").returns(true);
    const client = await createClient();
    featureStub.restore();

    try {
      await startClient(client);
    } catch (error: any) {
      assert.fail(`Failed to start server ${error.message}`);
    }

    assert.strictEqual(client.state, State.Running);

    try {
      await client.stop();
      await client.dispose();
    } catch (error: any) {
      assert.fail(`Failed to stop server: ${error.message}`);
    }
  }).timeout(60000);
});
