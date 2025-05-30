import * as assert from "assert";

import * as vscode from "vscode";
import * as sinon from "sinon";

import { ExecInReplCommandHandler } from "../../../commands/execInReplCommandHandler";
import { TerminalRepl } from "../../../terminalRepl";
import { Workspace } from "../../../workspace";
import { Command } from "../../../common";

suite("ExecInReplCommandHandler", () => {
  let sandbox: sinon.SinonSandbox;
  let handler: ExecInReplCommandHandler;
  let mockWorkspace: Workspace;
  let mockTerminalRepl: TerminalRepl;
  let currentActiveWorkspaceStub: sinon.SinonStub;
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
      execute: sandbox.stub().resolves(),
    } as any;

    currentActiveWorkspaceStub = sandbox.stub();
    getTerminalReplStub = sandbox.stub();

    handler = new ExecInReplCommandHandler(
      currentActiveWorkspaceStub,
      getTerminalReplStub,
    );

    // Mock VS Code APIs
    sandbox.stub(vscode.window, "showWarningMessage");
    sandbox.stub(vscode.window, "showInformationMessage");
    sandbox.stub(vscode.window, "showErrorMessage");
    sandbox.stub(vscode.commands, "executeCommand");
  });

  teardown(() => {
    sandbox.restore();
  });

  test("executes selected text when editor has selection", async () => {
    const mockEditor = {
      selection: {
        isEmpty: false,
      },
      document: {
        getText: sandbox.stub().returns("puts 'Hello, World!'"),
      },
    } as any;

    sandbox.stub(vscode.window, "activeTextEditor").value(mockEditor);
    currentActiveWorkspaceStub.returns(mockWorkspace);
    getTerminalReplStub.returns(mockTerminalRepl);

    await handler.execute();

    assert.ok(
      (mockTerminalRepl.execute as sinon.SinonStub).calledWith(
        "puts 'Hello, World!'",
      ),
    );
  });

  test("executes current line when editor has no selection", async () => {
    const mockLine = {
      text: "puts 'Current line'",
    };

    const mockEditor = {
      selection: {
        isEmpty: true,
        active: { line: 5 },
      },
      document: {
        lineAt: sandbox.stub().returns(mockLine),
      },
    } as any;

    sandbox.stub(vscode.window, "activeTextEditor").value(mockEditor);
    currentActiveWorkspaceStub.returns(mockWorkspace);
    getTerminalReplStub.returns(mockTerminalRepl);

    await handler.execute();

    assert.ok(
      (mockTerminalRepl.execute as sinon.SinonStub).calledWith(
        "puts 'Current line'",
      ),
    );
  });

  test("prompts to start REPL when no REPL is running", async () => {
    const mockEditor = {
      selection: { isEmpty: true, active: { line: 0 } },
      document: { lineAt: () => ({ text: "test code" }) },
    } as any;

    sandbox.stub(vscode.window, "activeTextEditor").value(mockEditor);
    currentActiveWorkspaceStub.returns(mockWorkspace);
    getTerminalReplStub.returns(undefined);

    const showInfoStub = vscode.window
      .showInformationMessage as sinon.SinonStub;
    showInfoStub.resolves("Start REPL");

    await handler.execute();

    assert.ok(
      showInfoStub.calledWith(
        "No REPL is running for this workspace. Would you like to start one?",
        "Start REPL",
      ),
    );
    assert.ok(
      (vscode.commands.executeCommand as sinon.SinonStub).calledWith(
        Command.StartRepl,
      ),
    );
  });

  test("handles execution errors gracefully", async () => {
    const mockEditor = {
      selection: { isEmpty: true, active: { line: 0 } },
      document: { lineAt: () => ({ text: "invalid code" }) },
    } as any;

    const failingRepl = {
      isRunning: true,
      execute: sandbox.stub().rejects(new Error("Syntax error")),
    } as any;

    sandbox.stub(vscode.window, "activeTextEditor").value(mockEditor);
    currentActiveWorkspaceStub.returns(mockWorkspace);
    getTerminalReplStub.returns(failingRepl);

    await handler.execute();

    assert.ok(
      (vscode.window.showErrorMessage as sinon.SinonStub).calledWith(
        "Failed to execute in REPL: Syntax error",
      ),
    );
  });

  test("shows warning when no active editor", async () => {
    sandbox.stub(vscode.window, "activeTextEditor").value(undefined);

    await handler.execute();

    assert.ok(
      (vscode.window.showWarningMessage as sinon.SinonStub).calledWith(
        "No active editor found",
      ),
    );
  });

  test("shows warning when no workspace found", async () => {
    const mockEditor = {} as any;
    sandbox.stub(vscode.window, "activeTextEditor").value(mockEditor);
    currentActiveWorkspaceStub.returns(undefined);

    await handler.execute();

    assert.ok(
      (vscode.window.showWarningMessage as sinon.SinonStub).calledWith(
        "No workspace found for current file",
      ),
    );
  });
});
