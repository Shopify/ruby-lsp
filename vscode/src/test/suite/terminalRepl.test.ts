import * as assert from "assert";

import * as vscode from "vscode";
import * as sinon from "sinon";

import { TerminalRepl } from "../../terminalRepl";
import { Workspace } from "../../workspace";

suite("TerminalRepl", () => {
  let sandbox: sinon.SinonSandbox;
  let workspace: Workspace;
  let terminalRepl: TerminalRepl;
  let createTerminalStub: sinon.SinonStub;
  let mockTerminal: vscode.Terminal;

  setup(() => {
    sandbox = sinon.createSandbox();

    // Mock workspace
    workspace = {
      workspaceFolder: {
        uri: vscode.Uri.file("/test/workspace"),
      },
      ruby: {
        env: { TEST_ENV: "test" },
      },
    } as any;

    // Mock terminal
    mockTerminal = {
      show: sandbox.stub(),
      sendText: sandbox.stub(),
      dispose: sandbox.stub(),
    } as any;

    // Stub vscode.window.createTerminal
    createTerminalStub = sandbox
      .stub(vscode.window, "createTerminal")
      .returns(mockTerminal);

    // Stub vscode.window.terminals
    sandbox.stub(vscode.window, "terminals").value([mockTerminal]);

    // Stub configuration for REPL settings
    sandbox.stub(vscode.workspace, "getConfiguration").returns({
      get: (key: string) => {
        if (key === "showWelcomeMessage") return true;
        if (key === "executionFeedbackDuration") return 3000;
        if (key === "autoOpenScratchPad") return true;
        return undefined;
      },
    } as any);
  });

  teardown(() => {
    sandbox.restore();
    if (terminalRepl) {
      terminalRepl.dispose();
    }
  });

  test("constructor initializes with IRB type", () => {
    terminalRepl = new TerminalRepl(workspace, "irb");
    assert.strictEqual((terminalRepl as any).replType, "irb");
    assert.strictEqual((terminalRepl as any).workspace, workspace);
  });

  test("constructor initializes with Rails type", () => {
    terminalRepl = new TerminalRepl(workspace, "rails");
    assert.strictEqual((terminalRepl as any).replType, "rails");
    assert.strictEqual((terminalRepl as any).workspace, workspace);
  });

  test("start creates terminal with correct options for IRB", async () => {
    terminalRepl = new TerminalRepl(workspace, "irb");

    // Mock shouldUseBundleExec to return false
    sandbox.stub(terminalRepl as any, "shouldUseBundleExec").resolves(false);

    await terminalRepl.start();

    assert.ok(createTerminalStub.calledOnce);
    const terminalOptions = createTerminalStub.firstCall.args[0];
    assert.strictEqual(terminalOptions.name, "Ruby REPL (IRB, Direct)");
    assert.strictEqual(
      terminalOptions.cwd,
      workspace.workspaceFolder.uri.fsPath,
    );
    assert.ok(mockTerminal.show);

    // Check that the enhanced IRB command with options is sent
    const sendTextCalls = (mockTerminal.sendText as sinon.SinonStub).getCalls();
    const irbCommand = sendTextCalls.find((call) =>
      call.args[0].includes("irb --colorize --autocomplete"),
    );
    assert.ok(
      irbCommand,
      "Should send IRB command with colorize and autocomplete options",
    );
  });

  test("start creates terminal with correct options for Rails", async () => {
    terminalRepl = new TerminalRepl(workspace, "rails");

    // Mock shouldUseBundleExec to return true
    sandbox.stub(terminalRepl as any, "shouldUseBundleExec").resolves(true);

    await terminalRepl.start();

    assert.ok(createTerminalStub.calledOnce);
    const terminalOptions = createTerminalStub.firstCall.args[0];
    assert.strictEqual(terminalOptions.name, "Rails Console (Direct)");
    assert.ok(mockTerminal.show);

    // Check that the Rails console command is sent
    const sendTextCalls = (mockTerminal.sendText as sinon.SinonStub).getCalls();
    const railsCommand = sendTextCalls.find((call) =>
      call.args[0].includes("bundle exec rails console"),
    );
    assert.ok(railsCommand, "Should send Rails console command");
  });

  test("execute sends code to terminal", async () => {
    terminalRepl = new TerminalRepl(workspace, "irb");
    sandbox.stub(terminalRepl as any, "shouldUseBundleExec").resolves(false);

    await terminalRepl.start();
    await terminalRepl.execute("puts 'hello'");

    assert.ok(
      (mockTerminal.sendText as sinon.SinonStub).calledWith("puts 'hello'"),
    );
  });

  test("execute throws error when REPL not running", async () => {
    terminalRepl = new TerminalRepl(workspace, "irb");

    await assert.rejects(
      async () => terminalRepl.execute("puts 'hello'"),
      /REPL is not running/,
    );
  });

  test("interrupt sends Ctrl+C to terminal", async () => {
    terminalRepl = new TerminalRepl(workspace, "irb");
    sandbox.stub(terminalRepl as any, "shouldUseBundleExec").resolves(false);

    await terminalRepl.start();
    terminalRepl.interrupt();

    assert.ok(
      (mockTerminal.sendText as sinon.SinonStub).calledWith("\x03", false),
    );
  });

  test("isRunning returns true when terminal exists", async () => {
    terminalRepl = new TerminalRepl(workspace, "irb");
    sandbox.stub(terminalRepl as any, "shouldUseBundleExec").resolves(false);

    await terminalRepl.start();
    assert.strictEqual(terminalRepl.isRunning, true);
  });

  test("isRunning returns false when terminal doesn't exist", () => {
    terminalRepl = new TerminalRepl(workspace, "irb");
    assert.strictEqual(terminalRepl.isRunning, false);
  });

  test("dispose cleans up terminal", async () => {
    terminalRepl = new TerminalRepl(workspace, "irb");
    sandbox.stub(terminalRepl as any, "shouldUseBundleExec").resolves(false);

    await terminalRepl.start();
    terminalRepl.dispose();

    assert.ok((mockTerminal.dispose as sinon.SinonStub).calledOnce);
    assert.strictEqual((terminalRepl as any).terminal, undefined);
  });

  test("uses bundle exec when Gemfile exists", async () => {
    terminalRepl = new TerminalRepl(workspace, "irb");

    // Mock shouldUseBundleExec to return true
    sandbox.stub(terminalRepl as any, "shouldUseBundleExec").resolves(true);

    await terminalRepl.start();

    // Check that bundle exec is used with the enhanced options
    const sendTextCalls = (mockTerminal.sendText as sinon.SinonStub).getCalls();
    const bundleExecCommand = sendTextCalls.find((call) =>
      call.args[0].includes("bundle exec irb --colorize --autocomplete"),
    );
    assert.ok(bundleExecCommand, "Should use bundle exec with IRB options");
  });

  test("doesn't use bundle exec when Gemfile doesn't exist", async () => {
    terminalRepl = new TerminalRepl(workspace, "irb");

    // Mock shouldUseBundleExec to return false
    sandbox.stub(terminalRepl as any, "shouldUseBundleExec").resolves(false);

    await terminalRepl.start();

    // Check that IRB is called without bundle exec but with options
    const sendTextCalls = (mockTerminal.sendText as sinon.SinonStub).getCalls();
    const irbCommand = sendTextCalls.find(
      (call) => call.args[0] === "irb --colorize --autocomplete",
    );
    assert.ok(irbCommand, "Should call IRB directly with options");
  });

  test("onDidClose callback is called when terminal is closed", async () => {
    terminalRepl = new TerminalRepl(workspace, "irb");
    sandbox.stub(terminalRepl as any, "shouldUseBundleExec").resolves(false);

    // Set up callback
    const closeCallback = sandbox.stub();
    terminalRepl.onDidClose(closeCallback);

    await terminalRepl.start();

    // Get the onDidCloseTerminal listener that was registered
    const onDidCloseTerminalStub = sandbox.stub(
      vscode.window,
      "onDidCloseTerminal",
    );

    // Manually trigger the setupTerminalCloseListener to register our stub
    (terminalRepl as any).setupTerminalCloseListener();

    // Get the callback that was registered
    const registeredCallback = onDidCloseTerminalStub.firstCall.args[0];

    // Simulate terminal close by calling the registered callback
    registeredCallback(mockTerminal);

    // Verify callback was called
    assert.ok(closeCallback.calledOnce);

    // Verify terminal reference was cleared
    assert.strictEqual((terminalRepl as any).terminal, undefined);
  });

  test("terminal close listener is disposed when terminalRepl is disposed", async () => {
    terminalRepl = new TerminalRepl(workspace, "irb");
    sandbox.stub(terminalRepl as any, "shouldUseBundleExec").resolves(false);

    await terminalRepl.start();

    // Get reference to the listener
    const listener = (terminalRepl as any).terminalCloseListener;
    assert.ok(listener);

    // Dispose the terminalRepl
    terminalRepl.dispose();

    // Verify listener was disposed
    assert.strictEqual((terminalRepl as any).terminalCloseListener, undefined);
  });

  test("shows information message when terminal is closed", async () => {
    terminalRepl = new TerminalRepl(workspace, "irb");
    sandbox.stub(terminalRepl as any, "shouldUseBundleExec").resolves(false);

    // Stub showInformationMessage
    const showInfoStub = sandbox.stub(vscode.window, "showInformationMessage");

    await terminalRepl.start();

    // Get the onDidCloseTerminal listener that was registered
    const onDidCloseTerminalStub = sandbox.stub(
      vscode.window,
      "onDidCloseTerminal",
    );

    // Manually trigger the setupTerminalCloseListener to register our stub
    (terminalRepl as any).setupTerminalCloseListener();

    // Get the callback that was registered
    const registeredCallback = onDidCloseTerminalStub.firstCall.args[0];

    // Simulate terminal close
    registeredCallback(mockTerminal);

    // Verify information message was shown
    assert.ok(showInfoStub.calledWith("Ruby REPL has been closed"));
  });

  test("shows correct message for Rails console", async () => {
    terminalRepl = new TerminalRepl(workspace, "rails");
    sandbox.stub(terminalRepl as any, "shouldUseBundleExec").resolves(true);

    // Stub showInformationMessage
    const showInfoStub = sandbox.stub(vscode.window, "showInformationMessage");

    await terminalRepl.start();

    // Get the onDidCloseTerminal listener that was registered
    const onDidCloseTerminalStub = sandbox.stub(
      vscode.window,
      "onDidCloseTerminal",
    );

    // Manually trigger the setupTerminalCloseListener to register our stub
    (terminalRepl as any).setupTerminalCloseListener();

    // Get the callback that was registered
    const registeredCallback = onDidCloseTerminalStub.firstCall.args[0];

    // Simulate terminal close
    registeredCallback(mockTerminal);

    // Verify correct message for Rails
    assert.ok(showInfoStub.calledWith("Rails Console has been closed"));
  });
});
