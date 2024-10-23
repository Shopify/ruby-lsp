/* eslint-disable no-process-env */
import assert from "assert";
import path from "path";
import os from "os";
import fs from "fs";

import sinon from "sinon";
import * as vscode from "vscode";
import {
  State,
  DocumentHighlightKind,
  Hover,
  WorkDoneProgress,
  SemanticTokens,
  DocumentLink,
  WorkspaceSymbol,
  SymbolKind,
  CodeLens,
  FullDocumentDiagnosticReport,
  FoldingRange,
  TextEdit,
  SelectionRange,
  CodeAction,
  TextDocumentFilter,
  LocationLink,
} from "vscode-languageclient/node";
import { after, afterEach, before } from "mocha";

import { Ruby, ManagerIdentifier } from "../../ruby";
import Client from "../../client";
import { WorkspaceChannel } from "../../workspaceChannel";
import { RUBY_VERSION } from "../rubyVersion";

import { FAKE_TELEMETRY } from "./fakeTelemetry";

const [major, minor, _patch] = RUBY_VERSION.split(".");

class FakeLogger {
  receivedMessages = "";

  trace(message: string, ..._args: any[]): void {
    this.receivedMessages += message;
  }

  debug(message: string, ..._args: any[]): void {
    this.receivedMessages += message;
  }

  info(message: string, ..._args: any[]): void {
    this.receivedMessages += message;
  }

  warn(message: string, ..._args: any[]): void {
    this.receivedMessages += message;
  }

  error(error: string | Error, ..._args: any[]): void {
    this.receivedMessages += error.toString();
  }

  append(value: string): void {
    this.receivedMessages += value;
  }

  appendLine(value: string): void {
    this.receivedMessages += value;
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
  const fakeLogger = new FakeLogger();
  const outputChannel = new WorkspaceChannel("fake", fakeLogger as any);

  // Ensure that we're activating the correct Ruby version on CI
  if (process.env.CI) {
    if (os.platform() === "linux") {
      await vscode.workspace
        .getConfiguration("rubyLsp")
        .update(
          "rubyVersionManager",
          { identifier: ManagerIdentifier.Chruby },
          true,
        );

      fs.mkdirSync(path.join(os.homedir(), ".rubies"), { recursive: true });
      fs.symlinkSync(
        `/opt/hostedtoolcache/Ruby/${RUBY_VERSION}/x64`,
        path.join(os.homedir(), ".rubies", RUBY_VERSION),
      );
    } else if (os.platform() === "darwin") {
      await vscode.workspace
        .getConfiguration("rubyLsp")
        .update(
          "rubyVersionManager",
          { identifier: ManagerIdentifier.Chruby },
          true,
        );

      fs.mkdirSync(path.join(os.homedir(), ".rubies"), { recursive: true });
      fs.symlinkSync(
        `/Users/runner/hostedtoolcache/Ruby/${RUBY_VERSION}/arm64`,
        path.join(os.homedir(), ".rubies", RUBY_VERSION),
      );
    } else {
      await vscode.workspace
        .getConfiguration("rubyLsp")
        .update(
          "rubyVersionManager",
          { identifier: ManagerIdentifier.RubyInstaller },
          true,
        );

      fs.symlinkSync(
        path.join(
          "C:",
          "hostedtoolcache",
          "windows",
          "Ruby",
          RUBY_VERSION,
          "x64",
        ),
        path.join("C:", `Ruby${major}${minor}-${os.arch()}`),
      );
    }
  }

  const ruby = new Ruby(
    context,
    workspaceFolder,
    outputChannel,
    FAKE_TELEMETRY,
  );
  await ruby.activateRuby();
  ruby.env.RUBY_LSP_BYPASS_TYPECHECKER = "true";

  const virtualDocuments = new Map<string, string>();

  vscode.workspace.registerTextDocumentContentProvider("embedded-content", {
    provideTextDocumentContent: (uri) => {
      const originalUri = /^\/(.*)\.[^.]+$/.exec(uri.path)?.[1];

      if (!originalUri) {
        return "";
      }

      const decodedUri = decodeURIComponent(originalUri);
      return virtualDocuments.get(decodedUri);
    },
  });

  const client = new Client(
    context,
    FAKE_TELEMETRY,
    ruby,
    () => {},
    workspaceFolder,
    outputChannel,
    virtualDocuments,
  );

  client.clientOptions.initializationFailedHandler = (error) => {
    assert.fail(
      `Failed to start server ${error.message}\n${fakeLogger.receivedMessages}`,
    );
  };

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
    // 60000 should be plenty but we're seeing timeouts on Windows in CI

    // eslint-disable-next-line no-invalid-this
    this.timeout(90000);
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

    if (process.env.CI) {
      if (os.platform() === "linux" || os.platform() === "darwin") {
        fs.rmSync(path.join(os.homedir(), ".rubies"), {
          recursive: true,
          force: true,
        });
      } else {
        fs.rmSync(path.join("C:", `Ruby${major}${minor}-${os.arch()}`), {
          recursive: true,
          force: true,
        });
      }
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
    const response: LocationLink[] = await client.sendRequest(
      "textDocument/definition",
      {
        textDocument: {
          uri: documentUri.toString(),
        },
        position: { line: 0, character: 11 },
      },
    );

    assert.strictEqual(response.length, 1);
    assert.match(response[0].targetUri, /server\.rb/);
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
    const text = "# source://erb//erb.rb#1\ndef foo\nend";

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
    assert.match(response[0].target!, /erb\.rb/);
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

    assert.strictEqual(
      response.items[0].message,
      "mismatched indentations at 'end' with 'def' at 1",
    );
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

  test("selection range", async () => {
    const text = "class Foo\nend";

    await client.sendNotification("textDocument/didOpen", {
      textDocument: {
        uri: documentUri.toString(),
        version: 1,
        text,
      },
    });
    const response: SelectionRange[] = await client.sendRequest(
      "textDocument/selectionRange",
      {
        textDocument: {
          uri: documentUri.toString(),
        },
        positions: [{ line: 0, character: 0 }],
      },
    );

    const range = response[0].range;
    assert.strictEqual(range.start.line, 0);
    assert.strictEqual(range.end.line, 1);
    assert.strictEqual(range.start.character, 0);
    assert.strictEqual(range.end.character, 3);
  }).timeout(20000);

  test("on type formatting", async () => {
    const text = "class Foo\n\n\n";

    await client.sendNotification("textDocument/didOpen", {
      textDocument: {
        uri: documentUri.toString(),
        version: 1,
        text,
      },
    });
    const response: TextEdit[] = await client.sendRequest(
      "textDocument/onTypeFormatting",
      {
        textDocument: {
          uri: documentUri.toString(),
        },
        position: { line: 1, character: 2 },
        ch: "\n",
      },
    );

    assert.strictEqual(response.length, 3);
    assert.strictEqual(response[1].newText, "end");
  }).timeout(20000);

  test("code actions", async () => {
    const text = "class Foo\nend";

    await client.sendNotification("textDocument/didOpen", {
      textDocument: {
        uri: documentUri.toString(),
        version: 1,
        text,
      },
    });

    const response: CodeAction[] = await client.sendRequest(
      "textDocument/codeAction",
      {
        textDocument: {
          uri: documentUri.toString(),
        },
        range: { start: { line: 2 }, end: { line: 4 } },
        context: {
          diagnostics: [
            {
              range: {
                start: { line: 2, character: 0 },
                end: { line: 2, character: 0 },
              },
              message: "Layout/EmptyLines: Extra blank line detected.",
              data: {
                correctable: true,
                // eslint-disable-next-line @typescript-eslint/naming-convention
                code_actions: [
                  {
                    title: "Autocorrect Layout/EmptyLines",
                    kind: "quickfix",
                    isPreferred: true,
                    edit: {
                      documentChanges: [
                        {
                          textDocument: {
                            uri: documentUri.toString(),
                          },
                          edits: [
                            {
                              range: {
                                start: { line: 2, character: 0 },
                                end: { line: 3, character: 0 },
                              },
                              newText: "",
                            },
                          ],
                        },
                      ],
                    },
                  },
                ],
              },
              code: "Layout/EmptyLines",
              severity: 3,
              source: "RuboCop",
            },
          ],
        },
      },
    );

    const quickfix = response.find((action) => action.kind === "quickfix")!;
    assert.match(quickfix.title, /Autocorrect Layout\/EmptyLines/);
  }).timeout(20000);

  test("code action resolve", async () => {
    const text = "class Foo\nend";

    await client.sendNotification("textDocument/didOpen", {
      textDocument: {
        uri: documentUri.toString(),
        version: 1,
        text,
      },
    });

    const response: CodeAction = await client.sendRequest(
      "codeAction/resolve",
      {
        kind: "refactor.extract",
        title: "Refactor: Extract Variable",
        data: {
          range: {
            start: { line: 1, character: 1 },
            end: { line: 1, character: 3 },
          },
          uri: documentUri.toString(),
        },
      },
    );

    assert.strictEqual(response.title, "Refactor: Extract Variable");
  }).timeout(20000);

  test("document selectors match default gems and bundled gems appropriately", () => {
    const [
      workspaceRubyFilter,
      workspaceERBFilter,
      bundledGemsFilter,
      defaultPathFilter,
      defaultGemsFilter,
    ] = client.clientOptions.documentSelector!;

    assert.strictEqual(
      (workspaceRubyFilter as TextDocumentFilter).language!,
      "ruby",
    );

    assert.strictEqual(
      (workspaceRubyFilter as TextDocumentFilter).pattern!,
      `${workspaceUri.fsPath}/**/*`,
    );

    assert.strictEqual(
      (workspaceERBFilter as TextDocumentFilter).language!,
      "erb",
    );

    assert.strictEqual(
      (workspaceERBFilter as TextDocumentFilter).pattern!,
      `${workspaceUri.fsPath}/**/*`,
    );

    assert.match(
      (bundledGemsFilter as TextDocumentFilter).pattern!,
      new RegExp(`ruby\\/\\d\\.\\d\\.\\d\\/\\*\\*\\/\\*`),
    );

    assert.match(
      (defaultPathFilter as TextDocumentFilter).pattern!,
      /lib\/ruby\/gems\/\d\.\d\.\d\/\*\*\/\*/,
    );

    assert.match(
      (defaultGemsFilter as TextDocumentFilter).pattern!,
      /lib\/ruby\/\d\.\d\.\d\/\*\*\/\*/,
    );
  });

  test("requests for non existing documents do not crash the server", async () => {
    await assert.rejects(
      async () =>
        client.sendRequest("textDocument/documentSymbol", {
          textDocument: {
            uri: documentUri.toString(),
          },
        }),
      (error: any) => {
        assert.strictEqual(error.data, null);
        assert.strictEqual(error.code, -32602);
        return true;
      },
    );
  }).timeout(20000);

  test("delegate completion", async () => {
    await client.sendNotification("textDocument/didOpen", {
      textDocument: {
        uri: documentUri.toString(),
        version: 1,
        text: "",
      },
    });

    const text = ["<% @users.each do |user| %>", "  <di", "<% end %>"].join(
      "\n",
    );
    const uri = vscode.Uri.joinPath(
      workspaceUri,
      "lib",
      "ruby_lsp",
      "index.html.erb",
    ).toString();

    await client.sendNotification("textDocument/didOpen", {
      textDocument: {
        uri,
        version: 1,
        text,
        languageId: "erb",
      },
    });

    const stub = sinon
      .stub(vscode.commands, "executeCommand")
      .resolves({ items: [{ label: "div" }] });

    const response: vscode.CompletionList = await client.sendRequest(
      "textDocument/completion",
      {
        textDocument: {
          uri,
        },
        position: { line: 1, character: 5 },
        context: {},
      },
    );
    stub.restore();

    await client.sendNotification("textDocument/didClose", {
      textDocument: { uri },
    });

    assert.deepStrictEqual(
      response.items.map((item) => item.label),
      ["div"],
    );

    assert.ok(
      stub.calledWithExactly(
        "vscode.executeCompletionItemProvider",
        vscode.Uri.parse(
          `embedded-content://html/${encodeURIComponent(uri)}.html`,
        ),
        { line: 1, character: 5 },
        undefined,
      ),
    );
  }).timeout(20000);

  test("delegate hover", async () => {
    await client.sendNotification("textDocument/didOpen", {
      textDocument: {
        uri: documentUri.toString(),
        version: 1,
        text: "",
      },
    });

    const text = ["<% @users.each do |user| %>", "  <di", "<% end %>"].join(
      "\n",
    );
    const uri = vscode.Uri.joinPath(
      workspaceUri,
      "lib",
      "ruby_lsp",
      "index.html.erb",
    ).toString();

    await client.sendNotification("textDocument/didOpen", {
      textDocument: {
        uri,
        version: 1,
        text,
        languageId: "erb",
      },
    });

    const stub = sinon
      .stub(vscode.commands, "executeCommand")
      .resolves({ contents: { kind: "markdown", value: "Hello!" } });

    await client.sendRequest("textDocument/hover", {
      textDocument: {
        uri,
      },
      position: { line: 1, character: 5 },
    });
    stub.restore();

    await client.sendNotification("textDocument/didClose", {
      textDocument: { uri },
    });

    assert.ok(
      stub.calledWithExactly(
        "vscode.executeHoverProvider",
        vscode.Uri.parse(
          `embedded-content://html/${encodeURIComponent(uri)}.html`,
        ),
        { line: 1, character: 5 },
      ),
    );
  }).timeout(20000);

  test("delegate definition", async () => {
    await client.sendNotification("textDocument/didOpen", {
      textDocument: {
        uri: documentUri.toString(),
        version: 1,
        text: "",
      },
    });

    const text = ["<% @users.each do |user| %>", "  <di", "<% end %>"].join(
      "\n",
    );
    const uri = vscode.Uri.joinPath(
      workspaceUri,
      "lib",
      "ruby_lsp",
      "index.html.erb",
    ).toString();

    await client.sendNotification("textDocument/didOpen", {
      textDocument: {
        uri,
        version: 1,
        text,
        languageId: "erb",
      },
    });

    const stub = sinon.stub(vscode.commands, "executeCommand").resolves(null);

    await client.sendRequest("textDocument/definition", {
      textDocument: {
        uri,
      },
      position: { line: 1, character: 5 },
    });
    stub.restore();

    await client.sendNotification("textDocument/didClose", {
      textDocument: { uri },
    });

    assert.ok(
      stub.calledWithExactly(
        "vscode.executeDefinitionProvider",
        vscode.Uri.parse(
          `embedded-content://html/${encodeURIComponent(uri)}.html`,
        ),
        { line: 1, character: 5 },
      ),
    );
  }).timeout(20000);

  test("delegate signature help", async () => {
    await client.sendNotification("textDocument/didOpen", {
      textDocument: {
        uri: documentUri.toString(),
        version: 1,
        text: "",
      },
    });

    const text = [
      "<% @users.each do |user| %>",
      "  <div onclick='alert(;'>",
      "<% end %>",
    ].join("\n");
    const uri = vscode.Uri.joinPath(
      workspaceUri,
      "lib",
      "ruby_lsp",
      "index.html.erb",
    ).toString();

    await client.sendNotification("textDocument/didOpen", {
      textDocument: {
        uri,
        version: 1,
        text,
        languageId: "erb",
      },
    });

    const stub = sinon.stub(vscode.commands, "executeCommand").resolves(null);

    await client.sendRequest("textDocument/signatureHelp", {
      textDocument: {
        uri,
      },
      position: { line: 1, character: 23 },
      context: {},
    });
    stub.restore();

    await client.sendNotification("textDocument/didClose", {
      textDocument: { uri },
    });

    assert.ok(
      stub.calledWithExactly(
        "vscode.executeSignatureHelpProvider",
        vscode.Uri.parse(
          `embedded-content://html/${encodeURIComponent(uri)}.html`,
        ),
        { line: 1, character: 23 },
        undefined,
      ),
    );
  }).timeout(20000);

  test("delegate document highlight", async () => {
    await client.sendNotification("textDocument/didOpen", {
      textDocument: {
        uri: documentUri.toString(),
        version: 1,
        text: "",
      },
    });

    const text = [
      "<% @users.each do |user| %>",
      "  <div></div>",
      "<% end %>",
    ].join("\n");
    const uri = vscode.Uri.joinPath(
      workspaceUri,
      "lib",
      "ruby_lsp",
      "index.html.erb",
    ).toString();

    await client.sendNotification("textDocument/didOpen", {
      textDocument: {
        uri,
        version: 1,
        text,
        languageId: "erb",
      },
    });

    const stub = sinon.stub(vscode.commands, "executeCommand").resolves(null);

    await client.sendRequest("textDocument/documentHighlight", {
      textDocument: {
        uri,
      },
      position: { line: 1, character: 4 },
      context: {},
    });
    stub.restore();

    await client.sendNotification("textDocument/didClose", {
      textDocument: { uri },
    });

    assert.ok(
      stub.calledWithExactly(
        "vscode.executeDocumentHighlights",
        vscode.Uri.parse(
          `embedded-content://html/${encodeURIComponent(uri)}.html`,
        ),
        { line: 1, character: 4 },
      ),
    );
  }).timeout(20000);
});
