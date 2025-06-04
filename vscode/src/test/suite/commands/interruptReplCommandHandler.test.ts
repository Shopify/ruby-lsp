import * as assert from "assert";

import * as vscode from "vscode";
import * as sinon from "sinon";

import { InterruptReplCommandHandler } from "../../../commands/interruptReplCommandHandler";
import { TerminalRepl } from "../../../terminalRepl";
import { Workspace } from "../../../workspace";
import { Command } from "../../../common";

suite("InterruptReplCommandHandler", () => {
  let sandbox: sinon.SinonSandbox;
  let handler: InterruptReplCommandHandler;
  let mockWorkspace: Workspace;
  let mockTerminalRepl: TerminalRepl;
  let showWorkspacePickStub: sinon.SinonStub;
  let getTerminalReplStub: sinon.SinonStub;

  setup(() => {
    sandbox = sinon.createSandbox();

    mockWorkspace = {
      workspaceFolder: {
        uri: vscode.Uri.file("/test/workspace"),
      },
    } as any;

    mockTerminalRepl = {
      isRunning: true,
      interrupt: sandbox.stub(),
    } as any;

    showWorkspacePickStub = sandbox.stub();
    getTerminalReplStub = sandbox.stub();

    handler = new InterruptReplCommandHandler(
      showWorkspacePickStub,
      getTerminalReplStub,
    );

    // Mock VS Code APIs
    sandbox.stub(vscode.window, "showInformationMessage");
  });

  teardown(() => {
    sandbox.restore();
  });

  test("has correct command ID", () => {
    assert.strictEqual(handler.commandId, Command.InterruptRepl);
  });

  test("returns early when no workspace is selected", async () => {
    showWorkspacePickStub.resolves(undefined);

    await handler.execute();

    assert.ok(showWorkspacePickStub.calledOnce);
    assert.ok(getTerminalReplStub.notCalled);
    assert.ok(
      (vscode.window.showInformationMessage as sinon.SinonStub).notCalled,
    );
  });

  test("shows message when no REPL is running", async () => {
    showWorkspacePickStub.resolves(mockWorkspace);
    getTerminalReplStub.returns(undefined);

    await handler.execute();

    assert.ok(showWorkspacePickStub.calledOnce);
    assert.ok(
      getTerminalReplStub.calledWith(
        mockWorkspace.workspaceFolder.uri.toString(),
      ),
    );
    assert.ok(
      (vscode.window.showInformationMessage as sinon.SinonStub).calledWith(
        "No REPL is running for this workspace",
      ),
    );
  });

  test("shows message when REPL exists but is not running", async () => {
    const notRunningRepl = {
      isRunning: false,
      interrupt: sandbox.stub(),
    } as any;

    showWorkspacePickStub.resolves(mockWorkspace);
    getTerminalReplStub.returns(notRunningRepl);

    await handler.execute();

    assert.ok(showWorkspacePickStub.calledOnce);
    assert.ok(
      getTerminalReplStub.calledWith(
        mockWorkspace.workspaceFolder.uri.toString(),
      ),
    );
    assert.ok(notRunningRepl.interrupt.notCalled);
    assert.ok(
      (vscode.window.showInformationMessage as sinon.SinonStub).calledWith(
        "No REPL is running for this workspace",
      ),
    );
  });

  test("successfully interrupts running REPL", async () => {
    showWorkspacePickStub.resolves(mockWorkspace);
    getTerminalReplStub.returns(mockTerminalRepl);

    await handler.execute();

    assert.ok(showWorkspacePickStub.calledOnce);
    assert.ok(
      getTerminalReplStub.calledWith(
        mockWorkspace.workspaceFolder.uri.toString(),
      ),
    );
    assert.ok((mockTerminalRepl.interrupt as sinon.SinonStub).calledOnce);
    assert.ok(
      (vscode.window.showInformationMessage as sinon.SinonStub).calledWith(
        "REPL interrupted",
      ),
    );
  });

  test("calls getTerminalRepl with correct workspace key", async () => {
    const workspaceWithDifferentUri = {
      workspaceFolder: {
        uri: vscode.Uri.file("/different/workspace"),
      },
    } as any;

    showWorkspacePickStub.resolves(workspaceWithDifferentUri);
    getTerminalReplStub.returns(mockTerminalRepl);

    await handler.execute();

    assert.ok(
      getTerminalReplStub.calledWith(
        workspaceWithDifferentUri.workspaceFolder.uri.toString(),
      ),
    );
  });
});
