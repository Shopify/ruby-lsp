import * as assert from "assert";
import * as fs from "fs";
import * as path from "path";
import * as os from "os";

import * as vscode from "vscode";
import { State } from "vscode-languageclient/node";

import { Ruby } from "../../ruby";
import { Telemetry, TelemetryApi, TelemetryEvent } from "../../telemetry";
import Client from "../../client";
import { LOG_CHANNEL, asyncExec } from "../../common";
import { WorkspaceChannel } from "../../workspaceChannel";

class FakeApi implements TelemetryApi {
  public sentEvents: TelemetryEvent[];

  constructor() {
    this.sentEvents = [];
  }

  // eslint-disable-next-line @typescript-eslint/require-await
  async sendEvent(event: TelemetryEvent): Promise<void> {
    this.sentEvents.push(event);
  }
}

suite("Client", () => {
  const context = {
    extensionMode: vscode.ExtensionMode.Test,
    subscriptions: [],
    workspaceState: {
      get: (_name: string) => undefined,
      update: (_name: string, _value: any) => Promise.resolve(),
    },
  } as unknown as vscode.ExtensionContext;

  test("Starting up the server succeeds", async () => {
    const tmpPath = fs.mkdtempSync(
      path.join(os.tmpdir(), "ruby-lsp-test-client"),
    );
    const workspaceFolder: vscode.WorkspaceFolder = {
      uri: vscode.Uri.from({ scheme: "file", path: tmpPath }),
      name: path.basename(tmpPath),
      index: 0,
    };
    fs.writeFileSync(path.join(tmpPath, ".ruby-version"), "3.3.0");

    const outputChannel = new WorkspaceChannel("fake", LOG_CHANNEL);
    const ruby = new Ruby(workspaceFolder, context, outputChannel);

    try {
      await ruby.activate();
    } catch (error: any) {
      assert.fail(`Failed to activate Ruby ${error.message}`);
    }

    await asyncExec("gem install ruby-lsp", {
      cwd: workspaceFolder.uri.fsPath,
      env: ruby.env,
    });

    const telemetry = new Telemetry(context, new FakeApi());
    const client = new Client(
      context,
      telemetry,
      ruby,
      () => {},
      workspaceFolder,
      outputChannel,
    );

    try {
      await client.start();
    } catch (error: any) {
      assert.fail(`Failed to start server ${error.message}`);
    }
    assert.strictEqual(client.state, State.Running);

    try {
      await client.stop();
      await client.dispose();
    } catch (error: any) {
      assert.fail(`Failed to stop server ${error.message}`);
    }

    try {
      fs.rmSync(tmpPath, { recursive: true, force: true });
    } catch (error: any) {
      // On Windows, sometimes removing the directory fails with EBUSY on CI
    }
  }).timeout(60000);
});
