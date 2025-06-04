import * as assert from "assert";

import * as vscode from "vscode";
import * as sinon from "sinon";

import { ExecuteScratchPadSelectionCommandHandler } from "../../../commands/executeScratchPadSelectionCommandHandler";
import { ReplScratchPad } from "../../../replScratchPad";
import { TerminalRepl } from "../../../terminalRepl";
import { Workspace } from "../../../workspace";
import { Command } from "../../../common";

suite("ExecuteScratchPadSelectionCommandHandler", () => {
  let sandbox: sinon.SinonSandbox;
  let handler: ExecuteScratchPadSelectionCommandHandler;
  let mockWorkspace: Workspace;
  let mockScratchPad: ReplScratchPad;
  let mockEditor: vscode.TextEditor;
  let mockTerminalRepl: TerminalRepl;
  // Using any to allow property modification
  let mockDocument: any;
  let currentActiveWorkspaceStub: sinon.SinonStub;
  let getScratchPadStub: sinon.SinonStub;
  let getTerminalReplStub: sinon.SinonStub;

  setup(() => {
    sandbox = sinon.createSandbox();

    mockWorkspace = {
      workspaceFolder: {
        uri: vscode.Uri.file("/test/workspace"),
      },
    } as any;

    mockTerminalRepl = {
      execute: sandbox.stub().resolves(),
    } as any;

    mockScratchPad = {
      getSelectionCode: sandbox.stub().returns({
        code: "puts 'selection'",
        lineNumber: 1,
      }),
      showExecutionSuccess: sandbox.stub(),
      showExecutionError: sandbox.stub(),
    } as any;

    mockDocument = {
      isUntitled: true,
      languageId: "ruby",
    };

    mockEditor = {
      selection: { active: { line: 0 }, isEmpty: false },
      document: mockDocument,
    } as any;

    currentActiveWorkspaceStub = sandbox.stub();
    getScratchPadStub = sandbox.stub();
    getTerminalReplStub = sandbox.stub().returns(mockTerminalRepl);

    handler = new ExecuteScratchPadSelectionCommandHandler(
      currentActiveWorkspaceStub,
      getScratchPadStub,
      getTerminalReplStub,
    );

    // Mock VS Code APIs
    sandbox.stub(vscode.window, "activeTextEditor").value(mockEditor);
    sandbox.stub(vscode.window, "showWarningMessage");
  });

  teardown(() => {
    sandbox.restore();
  });

  test("has correct command ID", () => {
    assert.strictEqual(handler.commandId, Command.ExecuteScratchPadSelection);
  });

  test("returns early when no active editor", async () => {
    sandbox.stub(vscode.window, "activeTextEditor").value(undefined);

    await handler.execute();

    assert.ok(currentActiveWorkspaceStub.notCalled);
    assert.ok(getScratchPadStub.notCalled);
    assert.ok(getTerminalReplStub.notCalled);
  });

  test("returns early when document is not a scratch pad", async () => {
    mockDocument.isUntitled = false;

    await handler.execute();

    assert.ok(currentActiveWorkspaceStub.notCalled);
    assert.ok(getScratchPadStub.notCalled);
    assert.ok(getTerminalReplStub.notCalled);
  });

  test("returns early when document language is not Ruby", async () => {
    mockDocument.languageId = "javascript";

    await handler.execute();

    assert.ok(currentActiveWorkspaceStub.notCalled);
    assert.ok(getScratchPadStub.notCalled);
    assert.ok(getTerminalReplStub.notCalled);
  });

  test("returns early when no workspace found", async () => {
    currentActiveWorkspaceStub.returns(undefined);

    await handler.execute();

    assert.ok(currentActiveWorkspaceStub.calledOnceWith(mockEditor));
    assert.ok(getScratchPadStub.notCalled);
    assert.ok(getTerminalReplStub.notCalled);
  });

  test("shows warning when no scratch pad found", async () => {
    currentActiveWorkspaceStub.returns(mockWorkspace);
    getScratchPadStub.returns(undefined);

    await handler.execute();

    assert.ok(currentActiveWorkspaceStub.calledOnceWith(mockEditor));
    assert.ok(
      getScratchPadStub.calledOnceWith(
        mockWorkspace.workspaceFolder.uri.toString(),
      ),
    );
    assert.ok(getTerminalReplStub.notCalled);
    assert.ok(
      (vscode.window.showWarningMessage as sinon.SinonStub).calledWith(
        "No scratch pad found for this workspace",
      ),
    );
  });

  test("shows warning when no terminal REPL found", async () => {
    currentActiveWorkspaceStub.returns(mockWorkspace);
    getScratchPadStub.returns(mockScratchPad);
    getTerminalReplStub.returns(undefined);

    await handler.execute();

    assert.ok(currentActiveWorkspaceStub.calledOnceWith(mockEditor));
    assert.ok(
      getScratchPadStub.calledOnceWith(
        mockWorkspace.workspaceFolder.uri.toString(),
      ),
    );
    assert.ok(
      getTerminalReplStub.calledOnceWith(
        mockWorkspace.workspaceFolder.uri.toString(),
      ),
    );
    assert.ok(
      (vscode.window.showWarningMessage as sinon.SinonStub).calledWith(
        "No REPL found for this workspace",
      ),
    );
  });

  test("returns early when code is not executable", async () => {
    currentActiveWorkspaceStub.returns(mockWorkspace);
    getScratchPadStub.returns(mockScratchPad);
    (mockScratchPad.getSelectionCode as sinon.SinonStub).returns({
      code: "# comment",
      lineNumber: 1,
    });

    await handler.execute();

    assert.ok(
      (mockScratchPad.getSelectionCode as sinon.SinonStub).calledOnceWith(
        mockEditor,
      ),
    );
    assert.ok((mockTerminalRepl.execute as sinon.SinonStub).notCalled);
    assert.ok(
      (mockScratchPad.showExecutionSuccess as sinon.SinonStub).notCalled,
    );
  });

  test("successfully executes selection", async () => {
    currentActiveWorkspaceStub.returns(mockWorkspace);
    getScratchPadStub.returns(mockScratchPad);

    await handler.execute();

    assert.ok(currentActiveWorkspaceStub.calledOnceWith(mockEditor));
    assert.ok(
      getScratchPadStub.calledOnceWith(
        mockWorkspace.workspaceFolder.uri.toString(),
      ),
    );
    assert.ok(
      getTerminalReplStub.calledOnceWith(
        mockWorkspace.workspaceFolder.uri.toString(),
      ),
    );
    assert.ok(
      (mockScratchPad.getSelectionCode as sinon.SinonStub).calledOnceWith(
        mockEditor,
      ),
    );
    assert.ok(
      (mockTerminalRepl.execute as sinon.SinonStub).calledOnceWith(
        "puts 'selection'",
      ),
    );
    assert.ok(
      (mockScratchPad.showExecutionSuccess as sinon.SinonStub).calledOnceWith(
        mockEditor,
        1,
      ),
    );
  });

  test("handles execution errors", async () => {
    currentActiveWorkspaceStub.returns(mockWorkspace);
    getScratchPadStub.returns(mockScratchPad);
    (mockTerminalRepl.execute as sinon.SinonStub).rejects(
      new Error("Execution failed"),
    );

    await handler.execute();

    assert.ok(
      (mockScratchPad.getSelectionCode as sinon.SinonStub).calledOnceWith(
        mockEditor,
      ),
    );
    assert.ok(
      (mockTerminalRepl.execute as sinon.SinonStub).calledOnceWith(
        "puts 'selection'",
      ),
    );
    assert.ok(
      (mockScratchPad.showExecutionError as sinon.SinonStub).calledOnceWith(
        mockEditor,
        1,
        "Execution failed",
      ),
    );
  });

  suite("Document validation", () => {
    test("validates scratch pad document correctly - saved Ruby file", async () => {
      mockDocument.isUntitled = false;
      mockDocument.languageId = "ruby";

      await handler.execute();

      // Should return early because saved files are not scratch pads
      assert.ok(currentActiveWorkspaceStub.notCalled);
    });

    test("validates scratch pad document correctly - untitled non-Ruby file", async () => {
      mockDocument.isUntitled = true;
      mockDocument.languageId = "typescript";

      await handler.execute();

      // Should return early because non-Ruby files are not scratch pads
      assert.ok(currentActiveWorkspaceStub.notCalled);
    });

    test("validates scratch pad document correctly - valid scratch pad", async () => {
      mockDocument.isUntitled = true;
      mockDocument.languageId = "ruby";
      currentActiveWorkspaceStub.returns(mockWorkspace);
      getScratchPadStub.returns(mockScratchPad);

      await handler.execute();

      // Should proceed to execution
      assert.ok(currentActiveWorkspaceStub.calledOnce);
      assert.ok(getScratchPadStub.calledOnce);
      assert.ok(getTerminalReplStub.calledOnce);
    });
  });
});
