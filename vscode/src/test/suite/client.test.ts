import * as assert from "assert";
import * as path from "path";
import os from "os";

import * as vscode from "vscode";
import {
  State,
  DocumentHighlightKind,
  Hover,
  WorkDoneProgress,
  Location,
  SemanticTokens,
  DocumentLink,
  WorkspaceSymbol,
  SymbolKind,
  CodeLens,
  FullDocumentDiagnosticReport,
  FoldingRange,
  TextEdit,
} from "vscode-languageclient/node";
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
  ruby.env.RUBY_LSP_BYPASS_TYPECHECKER = "true";

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

  // Wait for indexing to complete and only resolve the promise once we received the workdone progress end notification
  // (signifying indexing is complete)
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

  test("document highlight", async () => {
    const text = "$foo = 1";

    await client.sendNotification("textDocument/didOpen", {
      textDocument: {
        uri: documentUri.toString(),
        version: 1,
        text,
      },
    });
    const response: vscode.DocumentHighlight[] = await client.sendRequest(
      "textDocument/documentHighlight",
      {
        textDocument: {
          uri: documentUri.toString(),
        },
        position: { line: 0, character: 1 },
      },
    );

    assert.strictEqual(response.length, 1);
    assert.strictEqual(response[0].kind, DocumentHighlightKind.Write);
  }).timeout(20000);

  test("hover", async () => {
    const text = "RubyLsp::Server";

    await client.sendNotification("textDocument/didOpen", {
      textDocument: {
        uri: documentUri.toString(),
        version: 1,
        text,
      },
    });
    const response: Hover = await client.sendRequest("textDocument/hover", {
      textDocument: {
        uri: documentUri.toString(),
      },
      position: { line: 0, character: 11 },
    });

    const value = (response.contents as unknown as vscode.MarkdownString).value;
    assert.match(value, /RubyLsp::Server/);
    assert.match(value, /\*\*Definitions\*\*/);
    assert.match(value, /\[server.rb\]\(file/);
  }).timeout(20000);

  test("definition", async () => {
    const text = "RubyLsp::Server";

    await client.sendNotification("textDocument/didOpen", {
      textDocument: {
        uri: documentUri.toString(),
        version: 1,
        text,
      },
    });
    const response: Location[] = await client.sendRequest(
      "textDocument/definition",
      {
        textDocument: {
          uri: documentUri.toString(),
        },
        position: { line: 0, character: 11 },
      },
    );

    assert.strictEqual(response.length, 1);
    assert.match(response[0].uri, /server\.rb/);
  }).timeout(20000);

  test("semantic highlighting", async () => {
    const text = "foo";

    await client.sendNotification("textDocument/didOpen", {
      textDocument: {
        uri: documentUri.toString(),
        version: 1,
        text,
      },
    });
    const response: SemanticTokens = await client.sendRequest(
      "textDocument/semanticTokens/full",
      {
        textDocument: {
          uri: documentUri.toString(),
        },
      },
    );

    assert.deepStrictEqual(response.data, [0, 0, 3, 13, 0]);
  }).timeout(20000);

  test("document link", async () => {
    const text = "# source://mutex_m//mutex_m.rb#1\ndef foo\nend";

    await client.sendNotification("textDocument/didOpen", {
      textDocument: {
        uri: documentUri.toString(),
        version: 1,
        text,
      },
    });
    const response: DocumentLink[] = await client.sendRequest(
      "textDocument/documentLink",
      {
        textDocument: {
          uri: documentUri.toString(),
        },
      },
    );

    assert.strictEqual(response.length, 1);
    assert.match(response[0].target!, /mutex_m\.rb/);
  }).timeout(20000);

  test("workspace symbol", async () => {
    const response: WorkspaceSymbol[] = await client.sendRequest(
      "workspace/symbol",
      {},
    );

    const server = response.find(
      (symbol) => symbol.name === "RubyLsp::Server",
    )!;
    assert.strictEqual(server.name, "RubyLsp::Server");
    assert.strictEqual(server.kind, SymbolKind.Class);
  }).timeout(20000);

  test("code lens", async () => {
    const text = [
      "require 'test_helper'",
      "",
      "class MyTest < Minitest::Test",
      "  def test_foo",
      "    assert true",
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
    const response: CodeLens[] = await client.sendRequest(
      "textDocument/codeLens",
      {
        textDocument: {
          uri: documentUri.toString(),
        },
      },
    );

    // 3 for the class, 3 for the example
    assert.strictEqual(response.length, 6);
  }).timeout(20000);

  test("diagnostic", async () => {
    const text = "  def foo\n end";

    await client.sendNotification("textDocument/didOpen", {
      textDocument: {
        uri: documentUri.toString(),
        version: 1,
        text,
      },
    });
    const response: FullDocumentDiagnosticReport = await client.sendRequest(
      "textDocument/diagnostic",
      {
        textDocument: {
          uri: documentUri.toString(),
        },
      },
    );

    const expectedMessage =
      os.platform() === "win32"
        ? /Layout\/EndOfLine: Carriage return character missing/
        : /Style\/FrozenStringLiteralComment: Missing magic comment/;

    assert.match(response.items[0].message, expectedMessage);
  }).timeout(20000);

  test("folding range", async () => {
    const text = "def foo\n  1\nend";

    await client.sendNotification("textDocument/didOpen", {
      textDocument: {
        uri: documentUri.toString(),
        version: 1,
        text,
      },
    });
    const response: FoldingRange[] = await client.sendRequest(
      "textDocument/foldingRange",
      {
        textDocument: {
          uri: documentUri.toString(),
        },
      },
    );

    assert.strictEqual(response.length, 1);
    assert.strictEqual(response[0].kind, "region");
  }).timeout(20000);

  test("formatting", async () => {
    const text = "  def foo\n end";

    await client.sendNotification("textDocument/didOpen", {
      textDocument: {
        uri: documentUri.toString(),
        version: 1,
        text,
      },
    });
    const response: TextEdit[] = await client.sendRequest(
      "textDocument/formatting",
      {
        textDocument: {
          uri: documentUri.toString(),
        },
      },
    );

    const expected = [
      "# typed: strict",
      "# frozen_string_literal: true",
      "",
      "def foo",
      "end",
      "",
    ].join("\n");

    assert.strictEqual(response[0].newText, expected);
  }).timeout(20000);
});
