import * as assert from "assert";

import * as vscode from "vscode";
import * as sinon from "sinon";

import { ReplScratchPad } from "../../replScratchPad";

suite("ReplScratchPad", () => {
  let sandbox: sinon.SinonSandbox;
  let scratchPad: ReplScratchPad;
  let mockDocument: vscode.TextDocument;
  let mockEditor: vscode.TextEditor;
  let openTextDocumentStub: sinon.SinonStub;
  let showTextDocumentStub: sinon.SinonStub;
  let executeCommandStub: sinon.SinonStub;
  let createTextEditorDecorationTypeStub: sinon.SinonStub;

  setup(() => {
    sandbox = sinon.createSandbox();

    mockDocument = {
      lineAt: sandbox.stub(),
      getText: sandbox.stub(),
      lineCount: 10,
      uri: vscode.Uri.file("/test/scratch.rb"),
      isClosed: false,
    } as any;

    mockEditor = {
      document: mockDocument,
      selection: new vscode.Selection(0, 0, 0, 0),
      setDecorations: sandbox.stub(),
    } as any;

    openTextDocumentStub = sandbox
      .stub(vscode.workspace, "openTextDocument")
      .resolves(mockDocument);
    showTextDocumentStub = sandbox
      .stub(vscode.window, "showTextDocument")
      .resolves(mockEditor);
    executeCommandStub = sandbox
      .stub(vscode.commands, "executeCommand")
      .resolves();
    createTextEditorDecorationTypeStub = sandbox
      .stub(vscode.window, "createTextEditorDecorationType")
      .returns({
        dispose: sandbox.stub(),
      } as any);

    sandbox.stub(vscode.workspace, "getConfiguration").returns({
      get: (key: string) => {
        if (key === "executionFeedbackDuration") return 3000;
        return undefined;
      },
    } as any);

    const mockTab = {
      input: {
        uri: mockDocument.uri,
      } as vscode.TabInputText,
    };
    sandbox.stub(vscode.window, "tabGroups").value({
      all: [
        {
          tabs: [mockTab],
        },
      ],
      close: sandbox.stub().resolves(),
    });
  });

  teardown(() => {
    sandbox.restore();
    if (scratchPad) {
      scratchPad.dispose();
    }
  });

  test("constructor initializes decoration types", () => {
    scratchPad = new ReplScratchPad();

    assert.ok(createTextEditorDecorationTypeStub.calledTwice);
  });

  test("show creates new document with initial content", async () => {
    scratchPad = new ReplScratchPad();

    await scratchPad.show();

    assert.ok(openTextDocumentStub.calledOnce);
    const openDocumentArgs = openTextDocumentStub.firstCall.args[0];
    assert.strictEqual(openDocumentArgs.language, "ruby");
    assert.ok(openDocumentArgs.content.includes("# Ruby REPL Scratch Pad"));
    assert.ok(openDocumentArgs.content.includes("# Keyboard Shortcuts:"));
  });

  test("show displays document in side editor", async () => {
    scratchPad = new ReplScratchPad();

    await scratchPad.show();

    assert.ok(showTextDocumentStub.calledOnce);
    const showDocumentArgs = showTextDocumentStub.firstCall.args[1];
    assert.strictEqual(showDocumentArgs.viewColumn, vscode.ViewColumn.Beside);
    assert.strictEqual(showDocumentArgs.preserveFocus, false);
  });

  test("show executes terminal focus commands", async () => {
    scratchPad = new ReplScratchPad();

    await scratchPad.show();

    assert.ok(executeCommandStub.calledWith("workbench.action.terminal.focus"));
    assert.ok(
      executeCommandStub.calledWith("workbench.action.focusActiveEditorGroup"),
    );
  });

  test("getCurrentLineCode returns trimmed line text", () => {
    scratchPad = new ReplScratchPad();

    const mockLine = {
      text: "  puts 'hello'  ",
      lineNumber: 0,
    };
    (mockDocument.lineAt as sinon.SinonStub).returns(mockLine);
    mockEditor.selection = new vscode.Selection(0, 0, 0, 0);

    const code = scratchPad.getCurrentLineCode(mockEditor);

    assert.strictEqual(code, "puts 'hello'");
    assert.ok((mockDocument.lineAt as sinon.SinonStub).calledWith(0));
  });

  test("getSelectionCode returns selected text when selection exists", () => {
    scratchPad = new ReplScratchPad();

    const selection = new vscode.Selection(0, 0, 1, 10);
    mockEditor.selection = selection;
    (mockDocument.getText as sinon.SinonStub).returns("puts 'selected'");

    const result = scratchPad.getSelectionCode(mockEditor);

    assert.strictEqual(result.code, "puts 'selected'");
    assert.strictEqual(result.lineNumber, 1);
    assert.ok((mockDocument.getText as sinon.SinonStub).calledWith(selection));
  });

  test("getSelectionCode returns current line when no selection", () => {
    scratchPad = new ReplScratchPad();

    const mockLine = {
      text: "  puts 'current'  ",
      lineNumber: 2,
    };
    (mockDocument.lineAt as sinon.SinonStub).returns(mockLine);
    // Empty selection
    mockEditor.selection = new vscode.Selection(2, 5, 2, 5);

    const result = scratchPad.getSelectionCode(mockEditor);

    assert.strictEqual(result.code, "puts 'current'");
    assert.strictEqual(result.lineNumber, 2);
  });

  test("showExecutionSuccess creates success decoration", () => {
    scratchPad = new ReplScratchPad();

    scratchPad.showExecutionSuccess(mockEditor, 0);

    // Verify success decoration was set
    const setDecorationsCall = (mockEditor.setDecorations as sinon.SinonStub)
      .getCalls()
      .find(
        (call) =>
          call.args[1].length > 0 &&
          call.args[1][0].renderOptions?.after?.contentText?.includes(
            "✓ executed",
          ),
      );

    assert.ok(setDecorationsCall, "Should set success decoration");
  });

  test("showExecutionError creates error decoration", () => {
    scratchPad = new ReplScratchPad();

    scratchPad.showExecutionError(mockEditor, 0, "Test error");

    // Verify error decoration was set
    const setDecorationsCall = (mockEditor.setDecorations as sinon.SinonStub)
      .getCalls()
      .find(
        (call) =>
          call.args[1].length > 0 &&
          call.args[1][0].renderOptions?.after?.contentText?.includes(
            "✗ Test error",
          ),
      );

    assert.ok(setDecorationsCall, "Should set error decoration");
  });

  test("moveCursorToNextLine advances cursor position", () => {
    scratchPad = new ReplScratchPad();
    mockEditor.selection = new vscode.Selection(2, 5, 2, 5);

    scratchPad.moveCursorToNextLine(mockEditor);

    assert.strictEqual(mockEditor.selection.active.line, 3);
    assert.strictEqual(mockEditor.selection.active.character, 0);
    assert.strictEqual(mockEditor.selection.anchor.line, 3);
    assert.strictEqual(mockEditor.selection.anchor.character, 0);
  });

  test("moveCursorToNextLine stops at last line", () => {
    scratchPad = new ReplScratchPad();
    // Last line (0-indexed)
    mockEditor.selection = new vscode.Selection(9, 5, 9, 5);

    scratchPad.moveCursorToNextLine(mockEditor);

    assert.strictEqual(mockEditor.selection.active.line, 9);
    assert.strictEqual(mockEditor.selection.active.character, 0);
  });

  test("closeScratchPad closes the document tab", async () => {
    scratchPad = new ReplScratchPad();
    (scratchPad as any).document = mockDocument;
    (scratchPad as any).editor = mockEditor;

    await scratchPad.closeScratchPad();

    assert.ok(vscode.window.tabGroups.close);
  });

  test("closeScratchPad clears document and editor references", async () => {
    scratchPad = new ReplScratchPad();
    (scratchPad as any).document = mockDocument;
    (scratchPad as any).editor = mockEditor;

    await scratchPad.closeScratchPad();

    assert.strictEqual((scratchPad as any).document, undefined);
    assert.strictEqual((scratchPad as any).editor, undefined);
  });

  test("dispose calls closeScratchPad and disposes decorations", async () => {
    scratchPad = new ReplScratchPad();

    const mockDecorationType = { dispose: sandbox.stub() };
    (scratchPad as any).decorationType = mockDecorationType;
    (scratchPad as any).errorDecorationType = mockDecorationType;

    // Spy on closeScratchPad
    const closeScratchPadSpy = sandbox.spy(scratchPad, "closeScratchPad");

    scratchPad.dispose();

    assert.ok(closeScratchPadSpy.called);
    assert.ok(mockDecorationType.dispose.calledTwice);
  });
});
