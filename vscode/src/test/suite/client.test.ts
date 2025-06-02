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
  LocationLink,
  TextDocumentFilter,
  ShowMessageParams,
  MessageType,
} from "vscode-languageclient/node";
import { after, afterEach, before, setup } from "mocha";

import { Ruby, ManagerIdentifier } from "../../ruby";
import Client from "../../client";
import { WorkspaceChannel } from "../../workspaceChannel";
import { MAJOR, MINOR } from "../rubyVersion";

import { FAKE_TELEMETRY, FakeLogger } from "./fakeTelemetry";
import { createContext, createRubySymlinks } from "./helpers";

async function launchClient(workspaceUri: vscode.Uri) {
  const workspaceFolder: vscode.WorkspaceFolder = {
    uri: workspaceUri,
    name: path.basename(workspaceUri.fsPath),
    index: 0,
  };

  const context = createContext();
  const fakeLogger = new FakeLogger();
  const outputChannel = new WorkspaceChannel("fake", fakeLogger as any);

  let managerConfig;

  // Ensure that we're activating the correct Ruby version on CI
  if (process.env.CI) {
    await vscode.workspace
      .getConfiguration("rubyLsp")
      .update("formatter", "rubocop_internal", true);
    await vscode.workspace
      .getConfiguration("rubyLsp")
      .update("linters", ["rubocop_internal"], true);

    createRubySymlinks();

    if (os.platform() === "win32") {
      managerConfig = { identifier: ManagerIdentifier.RubyInstaller };
    } else {
      managerConfig = { identifier: ManagerIdentifier.Chruby };
    }
  }

  const ruby = new Ruby(
    context,
    workspaceFolder,
    outputChannel,
    FAKE_TELEMETRY,
  );
  await ruby.activateRuby(managerConfig);
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

  client.onNotification("window/showMessage", (params: ShowMessageParams) => {
    if (params.type === MessageType.Error) {
      assert.fail(`Server error: ${params.message}`);
    }
  });

  client.onNotification("window/logMessage", (params: ShowMessageParams) => {
    if (params.type === MessageType.Error) {
      assert.fail(`Server error: ${params.message}`);
    }
  });

  try {
    await client.start();
  } catch (error: any) {
    assert.fail(`Failed to start server ${error.message}`);
  }

  assert.strictEqual(client.state, State.Running);
  await client.waitForIndexing();
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
        fs.rmSync(path.join("C:", `Ruby${MAJOR}${MINOR}-${os.arch()}`), {
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
    const text = ["# frozen_string_literal: true", "", "def foo", "end"]
      .join("\n")
      .trim();

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
    ]
      .join("\n")
      .trim();

    assert.strictEqual(response[0].newText.trim(), expected);
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
        range: {
          start: { line: 0, character: 1 },
          end: { line: 0, character: 2 },
        },
        context: {
          diagnostics: [
            {
              range: {
                start: { line: 0, character: 0 },
                end: { line: 1, character: 2 },
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
    const selector = client.clientOptions
      .documentSelector! as TextDocumentFilter[];
    assert.strictEqual(selector.length, 5);

    // We don't care about the order of the document filters, just that they are present. This assertion helper is just
    // a convenience to search the registered filters
    const assertSelector = (
      language: string | undefined,
      pattern: RegExp | string,
      scheme: string | undefined,
    ) => {
      assert.ok(
        selector.find(
          (filter: TextDocumentFilter) =>
            filter.language === language &&
            (typeof pattern === "string"
              ? pattern === filter.pattern
              : pattern.test(filter.pattern!)) &&
            filter.scheme === scheme,
        ),
      );
    };

    assertSelector("ruby", `${workspaceUri.fsPath}/**/*`, "file");
    assertSelector("erb", `${workspaceUri.fsPath}/**/*`, "file");
    assertSelector(
      "ruby",
      new RegExp(`ruby\\/\\d\\.\\d\\.\\d\\/\\*\\*\\/\\*`),
      "file",
    );
    assertSelector("ruby", /lib\/ruby\/gems\/\d\.\d\.\d\/\*\*\/\*/, "file");
    assertSelector("ruby", /lib\/ruby\/\d\.\d\.\d\/\*\*\/\*/, "file");
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

  test("requests for documents that were not opened by the client", async () => {
    const uri = vscode.Uri.joinPath(
      workspaceUri,
      "lib",
      "ruby_lsp",
      "server.rb",
    );

    const response: vscode.DocumentSymbol[] = await client.sendRequest(
      "textDocument/documentSymbol",
      {
        textDocument: {
          uri: uri.toString(),
        },
      },
    );

    assert.ok(response.length > 0);
  }).timeout(20000);

  suite("goto relevant file", () => {
    let testUri: vscode.Uri;
    let implUri: vscode.Uri;

    setup(() => {
      testUri = vscode.Uri.joinPath(
        workspaceUri,
        "test",
        "requests",
        "go_to_relevant_file_test.rb",
      );
      implUri = vscode.Uri.joinPath(
        workspaceUri,
        "lib",
        "ruby_lsp",
        "requests",
        "go_to_relevant_file.rb",
      );
    });

    test("for test file", async () => {
      const response: { locations: string[] } = await client.sendRequest(
        "experimental/goToRelevantFile",
        {
          textDocument: {
            uri: testUri.toString(),
          },
        },
      );

      assert.ok(response.locations.length === 1);
      assert.match(
        response.locations[0],
        /lib\/ruby_lsp\/requests\/go_to_relevant_file\.rb$/,
      );
    }).timeout(20000);

    test("for implementation file", async () => {
      const response: { locations: string[] } = await client.sendRequest(
        "experimental/goToRelevantFile",
        {
          textDocument: {
            uri: implUri.toString(),
          },
        },
      );

      assert.ok(response.locations.length === 1);
      assert.match(
        response.locations[0],
        /test\/requests\/go_to_relevant_file_test\.rb$/,
      );
    }).timeout(20000);

    test("returns empty array for invalid file", async () => {
      const uri = vscode.Uri.joinPath(workspaceUri, "nonexistent", "file.rb");

      const response: { locations: string[] } = await client.sendRequest(
        "experimental/goToRelevantFile",
        {
          textDocument: {
            uri: uri.toString(),
          },
        },
      );

      assert.deepStrictEqual(response, { locations: [] });
    }).timeout(20000);
  });
});
