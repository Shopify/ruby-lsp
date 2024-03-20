import * as assert from "assert";
import * as path from "path";

import * as vscode from "vscode";
import { State } from "vscode-languageclient/node";
import { after, afterEach, before } from "mocha";

import { Ruby, ManagerIdentifier } from "../../ruby";
import { Telemetry, TelemetryApi, TelemetryEvent } from "../../telemetry";
import Client from "../../client";
import { LOG_CHANNEL } from "../../common";
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

async function launchClient(workspaceUri: vscode.Uri) {
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
  const outputChannel = new WorkspaceChannel("fake", LOG_CHANNEL);

  const ruby = new Ruby(context, workspaceFolder, outputChannel);
  await ruby.activateRuby();

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

  return client;
}

suite("Client", () => {
  const workspacePath = path.dirname(
    path.dirname(path.dirname(path.dirname(__dirname))),
  );
  const workspaceUri = vscode.Uri.file(workspacePath);
  const documentUri = vscode.Uri.joinPath(
    workspaceUri,
    "lib",
    "ruby_lsp",
    "fake.rb",
  );
  let client: Client;

  before(async function () {
    // eslint-disable-next-line no-invalid-this
    this.timeout(60000);

    // eslint-disable-next-line no-process-env
    if (process.env.CI) {
      await vscode.workspace
        .getConfiguration("rubyLsp")
        .update("rubyVersionManager", ManagerIdentifier.None, true, true);
    }
    client = await launchClient(workspaceUri);
  });

  after(async function () {
    // eslint-disable-next-line no-invalid-this
    this.timeout(20000);

    try {
      await client.stop();
      await client.dispose();
    } catch (error: any) {
      assert.fail(`Failed to stop server: ${error.message}`);
    }
  });

  afterEach(async () => {
    await client.sendNotification("textDocument/didClose", {
      textDocument: {
        uri: documentUri.toString(),
      },
    });
  });

  test("document symbol", async () => {
    const text = [
      "class Foo",
      "  def initialize",
      "    @bar = 1",
      "  end",
      "end",
    ].join("\n");

    await client.sendNotification("textDocument/didOpen", {
      textDocument: {
        uri: documentUri.toString(),
        version: 1,
        text,
      },
    });
    const response: vscode.DocumentSymbol[] = await client.sendRequest(
      "textDocument/documentSymbol",
      {
        textDocument: {
          uri: documentUri.toString(),
        },
      },
    );

    assert.strictEqual(response[0].name, "Foo");
    assert.strictEqual(response[0].children[0].name, "initialize");
    assert.strictEqual(response[0].children[0].children[0].name, "@bar");
  }).timeout(20000);
});
