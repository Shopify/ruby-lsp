import * as assert from "assert";

import * as vscode from "vscode";
import * as sinon from "sinon";

import { ReplManager } from "../../replManager";
import { RubyLspTerminalProfileProvider } from "../../terminalProfileProvider";
import { Workspace } from "../../workspace";
import { Command } from "../../common";

suite("ReplManager", () => {
  let sandbox: sinon.SinonSandbox;
  let replManager: ReplManager;
  let mockContext: vscode.ExtensionContext;
  let mockWorkspace: Workspace;
  let getWorkspacesStub: sinon.SinonStub;
  let showWorkspacePickStub: sinon.SinonStub;
  let currentActiveWorkspaceStub: sinon.SinonStub;

  setup(() => {
    sandbox = sinon.createSandbox();

    mockContext = {
      subscriptions: [],
    } as any;

    mockWorkspace = {
      workspaceFolder: {
        uri: vscode.Uri.file("/test/workspace"),
      },
    } as any;

    getWorkspacesStub = sandbox.stub().returns([mockWorkspace]);
    showWorkspacePickStub = sandbox.stub().resolves(mockWorkspace);
    currentActiveWorkspaceStub = sandbox.stub().returns(mockWorkspace);

    sandbox.stub(RubyLspTerminalProfileProvider.prototype, "register");
    sandbox.stub(RubyLspTerminalProfileProvider.prototype, "updateWorkspaces");
    sandbox.stub(RubyLspTerminalProfileProvider.prototype, "dispose");

    sandbox.stub(vscode.workspace, "getConfiguration").returns({
      get: () => true,
    } as any);

    sandbox.stub(vscode.commands, "registerCommand").returns({
      dispose: sandbox.stub(),
    } as any);

    replManager = new ReplManager(
      mockContext,
      getWorkspacesStub,
      showWorkspacePickStub,
      currentActiveWorkspaceStub,
    );
  });

  teardown(() => {
    sandbox.restore();
    if (replManager) {
      replManager.dispose();
    }
  });

  test("register returns command disposables", () => {
    const disposables = replManager.register();

    assert.ok(Array.isArray(disposables));
    assert.ok(disposables.length > 0);
  });

  test("register calls terminal profile provider register", () => {
    replManager.register();

    assert.ok(
      (
        RubyLspTerminalProfileProvider.prototype.register as sinon.SinonStub
      ).calledWith(mockContext),
    );
  });

  test("updateWorkspaces delegates to terminal profile provider", async () => {
    await replManager.updateWorkspaces();

    assert.ok(
      (
        RubyLspTerminalProfileProvider.prototype
          .updateWorkspaces as sinon.SinonStub
      ).calledWith([mockWorkspace]),
    );
  });

  test("dispose cleans up terminal profile provider", () => {
    replManager.dispose();

    assert.ok(
      (RubyLspTerminalProfileProvider.prototype.dispose as sinon.SinonStub)
        .calledOnce,
    );
  });

  test("registerRepl manages REPL lifecycle", () => {
    const terminalRepls = (replManager as any).terminalRepls;
    const mockRepl = { dispose: sandbox.stub() };

    // Add an existing REPL
    terminalRepls.set("workspace1", mockRepl);

    // Register a new REPL for the same workspace
    const newRepl = { dispose: sandbox.stub() };
    (replManager as any).registerRepl("workspace1", newRepl);

    // Should dispose old REPL and register new one
    assert.ok(mockRepl.dispose.calledOnce);
    assert.strictEqual(terminalRepls.get("workspace1"), newRepl);
  });

  test("unregisterRepl cleans up resources", () => {
    const terminalRepls = (replManager as any).terminalRepls;
    const replScratchPads = (replManager as any).replScratchPads;

    const mockRepl = { dispose: sandbox.stub() };
    const mockScratchPad = { dispose: sandbox.stub() };

    terminalRepls.set("workspace1", mockRepl);
    replScratchPads.set("workspace1", mockScratchPad);

    (replManager as any).unregisterRepl("workspace1");

    assert.ok(mockRepl.dispose.calledOnce);
    assert.ok(mockScratchPad.dispose.calledOnce);
    assert.ok(!terminalRepls.has("workspace1"));
    assert.ok(!replScratchPads.has("workspace1"));
  });

  test("registerScratchPad manages scratch pad lifecycle", () => {
    const replScratchPads = (replManager as any).replScratchPads;
    const existingScratchPad = { dispose: sandbox.stub() };
    replScratchPads.set("workspace1", existingScratchPad);

    const newScratchPad = { dispose: sandbox.stub() };
    (replManager as any).registerScratchPad("workspace1", newScratchPad);

    assert.ok(existingScratchPad.dispose.calledOnce);
    assert.strictEqual(replScratchPads.get("workspace1"), newScratchPad);
  });

  suite("Command registration", () => {
    test("registers all expected commands", () => {
      replManager.register();

      const registerCommandStub = vscode.commands
        .registerCommand as sinon.SinonStub;
      const commandNames = registerCommandStub
        .getCalls()
        .map((call) => call.args[0]);

      assert.ok(commandNames.includes(Command.StartRepl));
      assert.ok(commandNames.includes(Command.ExecInRepl));
      assert.ok(commandNames.includes(Command.InterruptRepl));
      assert.ok(commandNames.includes(Command.ExecuteScratchPadLine));
      assert.ok(commandNames.includes(Command.ExecuteScratchPadSelection));
    });

    test("each command has a callback function", () => {
      replManager.register();

      const registerCommandStub = vscode.commands
        .registerCommand as sinon.SinonStub;
      const calls = registerCommandStub.getCalls();

      calls.forEach((call) => {
        assert.ok(
          typeof call.args[1] === "function",
          `Command ${call.args[0]} should have a callback function`,
        );
      });
    });
  });
});
