import * as assert from "assert";

import * as vscode from "vscode";
import * as sinon from "sinon";

import { StartReplCommandHandler } from "../../../commands/startReplCommandHandler";
import { Workspace } from "../../../workspace";
import { Command } from "../../../common";

suite("StartReplCommandHandler", () => {
  let sandbox: sinon.SinonSandbox;
  let handler: StartReplCommandHandler;
  let mockWorkspace: Workspace;
  let showWorkspacePickStub: sinon.SinonStub;
  let startReplStub: sinon.SinonStub;

  setup(() => {
    sandbox = sinon.createSandbox();

    mockWorkspace = {
      workspaceFolder: {
        uri: vscode.Uri.file("/test/workspace"),
      },
    } as any;

    showWorkspacePickStub = sandbox.stub();
    startReplStub = sandbox.stub().resolves();

    handler = new StartReplCommandHandler(showWorkspacePickStub, startReplStub);

    // Mock VS Code APIs
    sandbox.stub(vscode.window, "showQuickPick");
    sandbox.stub(vscode.window, "showErrorMessage");
  });

  teardown(() => {
    sandbox.restore();
  });

  test("has correct command ID", () => {
    assert.strictEqual(handler.commandId, Command.StartRepl);
  });

  test("returns early when no workspace is selected", async () => {
    showWorkspacePickStub.resolves(undefined);

    await handler.execute();

    assert.ok(showWorkspacePickStub.calledOnce);
    assert.ok(startReplStub.notCalled);
    assert.ok((vscode.window.showQuickPick as sinon.SinonStub).notCalled);
  });

  test("returns early when no REPL type is selected", async () => {
    showWorkspacePickStub.resolves(mockWorkspace);
    (vscode.window.showQuickPick as sinon.SinonStub).resolves(undefined);

    await handler.execute();

    assert.ok(showWorkspacePickStub.calledOnce);
    assert.ok((vscode.window.showQuickPick as sinon.SinonStub).calledOnce);
    assert.ok(startReplStub.notCalled);
  });

  test("successfully starts IRB REPL", async () => {
    showWorkspacePickStub.resolves(mockWorkspace);
    (vscode.window.showQuickPick as sinon.SinonStub).resolves("irb");

    await handler.execute();

    assert.ok(showWorkspacePickStub.calledOnce);
    assert.ok((vscode.window.showQuickPick as sinon.SinonStub).calledOnce);
    assert.ok(startReplStub.calledOnceWith(mockWorkspace, "irb"));
  });

  test("successfully starts Rails REPL", async () => {
    showWorkspacePickStub.resolves(mockWorkspace);
    (vscode.window.showQuickPick as sinon.SinonStub).resolves("rails");

    await handler.execute();

    assert.ok(showWorkspacePickStub.calledOnce);
    assert.ok((vscode.window.showQuickPick as sinon.SinonStub).calledOnce);
    assert.ok(startReplStub.calledOnceWith(mockWorkspace, "rails"));
  });

  test("shows correct quick pick options", async () => {
    showWorkspacePickStub.resolves(mockWorkspace);
    (vscode.window.showQuickPick as sinon.SinonStub).resolves("irb");

    await handler.execute();

    assert.ok(
      (vscode.window.showQuickPick as sinon.SinonStub).calledWith(
        ["irb", "rails"],
        { placeHolder: "Select REPL type" },
      ),
    );
  });

  test("handles startRepl errors gracefully", async () => {
    showWorkspacePickStub.resolves(mockWorkspace);
    (vscode.window.showQuickPick as sinon.SinonStub).resolves("irb");
    startReplStub.rejects(new Error("Failed to start terminal"));

    await handler.execute();

    assert.ok(startReplStub.calledOnce);
    assert.ok(
      (vscode.window.showErrorMessage as sinon.SinonStub).calledWith(
        "Failed to start REPL: Failed to start terminal",
      ),
    );
  });

  test("handles startRepl errors without error details", async () => {
    showWorkspacePickStub.resolves(mockWorkspace);
    (vscode.window.showQuickPick as sinon.SinonStub).resolves("rails");
    startReplStub.rejects(new Error("Generic error"));

    await handler.execute();

    assert.ok(startReplStub.calledOnce);
    assert.ok(
      (vscode.window.showErrorMessage as sinon.SinonStub).calledWith(
        "Failed to start REPL: Generic error",
      ),
    );
  });
});
