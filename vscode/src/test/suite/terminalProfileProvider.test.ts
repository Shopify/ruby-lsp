import * as assert from "assert";
import path from "path";

import * as vscode from "vscode";
import * as sinon from "sinon";

import { RubyLspTerminalProfileProvider } from "../../terminalProfileProvider";
import { TerminalRepl } from "../../terminalRepl";
import { ReplScratchPad } from "../../replScratchPad";
import { Workspace } from "../../workspace";

suite("RubyLspTerminalProfileProvider", () => {
  let sandbox: sinon.SinonSandbox;
  let provider: RubyLspTerminalProfileProvider;
  let mockWorkspace: Workspace;
  let mockContext: vscode.ExtensionContext;
  let registerReplCallback: sinon.SinonStub;
  let unregisterReplCallback: sinon.SinonStub;
  let registerScratchPadCallback: sinon.SinonStub;
  let registerCommandStub: sinon.SinonStub;
  let registerTerminalProfileProviderStub: sinon.SinonStub;
  let onDidOpenTerminalStub: sinon.SinonStub;
  let getConfigurationStub: sinon.SinonStub;
  let getWorkspaceFolderStub: sinon.SinonStub;

  setup(() => {
    sandbox = sinon.createSandbox();

    mockWorkspace = {
      workspaceFolder: {
        uri: vscode.Uri.file(path.join("test", "workspace")),
      },
      ruby: {
        env: { TEST_ENV: "test" },
      },
    } as any;

    mockContext = {
      subscriptions: [],
    } as any;

    registerReplCallback = sandbox.stub();
    unregisterReplCallback = sandbox.stub();
    registerScratchPadCallback = sandbox.stub();

    registerCommandStub = sandbox
      .stub(vscode.commands, "registerCommand")
      .returns({
        dispose: sandbox.stub(),
      } as any);

    registerTerminalProfileProviderStub = sandbox
      .stub(vscode.window, "registerTerminalProfileProvider")
      .returns({
        dispose: sandbox.stub(),
      } as any);

    onDidOpenTerminalStub = sandbox
      .stub(vscode.window, "onDidOpenTerminal")
      .returns({
        dispose: sandbox.stub(),
      } as any);

    getConfigurationStub = sandbox
      .stub(vscode.workspace, "getConfiguration")
      .returns({
        get: (key: string) => {
          if (key === "autoOpenScratchPad") return true;
          if (key === "showWelcomeMessage") return true;
          return undefined;
        },
      } as any);

    sandbox.stub(vscode.window, "showErrorMessage");
    sandbox.stub(vscode.window, "showWarningMessage");
    sandbox.stub(vscode.window, "showInformationMessage");
    sandbox.stub(vscode.window, "activeTextEditor").value(undefined);

    getWorkspaceFolderStub = sandbox
      .stub(vscode.workspace, "getWorkspaceFolder")
      .returns(undefined);
  });

  teardown(() => {
    sandbox.restore();
    if (provider) {
      provider.dispose();
    }
  });

  test("constructor initializes with workspaces and callbacks", () => {
    provider = new RubyLspTerminalProfileProvider(
      [mockWorkspace],
      registerReplCallback,
      unregisterReplCallback,
      registerScratchPadCallback,
    );

    assert.strictEqual((provider as any).workspaces.length, 1);
    assert.strictEqual(
      (provider as any).registerReplCallback,
      registerReplCallback,
    );
    assert.strictEqual(
      (provider as any).unregisterReplCallback,
      unregisterReplCallback,
    );
    assert.strictEqual(
      (provider as any).registerScratchPadCallback,
      registerScratchPadCallback,
    );
  });

  test("constructor initializes without callbacks", () => {
    provider = new RubyLspTerminalProfileProvider([mockWorkspace]);

    assert.strictEqual((provider as any).workspaces.length, 1);
    assert.strictEqual((provider as any).registerReplCallback, undefined);
  });

  test("updateWorkspaces updates the workspaces array", async () => {
    provider = new RubyLspTerminalProfileProvider([]);
    assert.strictEqual((provider as any).workspaces.length, 0);

    await provider.updateWorkspaces([mockWorkspace]);
    assert.strictEqual((provider as any).workspaces.length, 1);
  });

  test("setCallbacks updates the callback functions", () => {
    provider = new RubyLspTerminalProfileProvider([mockWorkspace]);

    provider.setCallbacks(
      registerReplCallback,
      unregisterReplCallback,
      registerScratchPadCallback,
    );

    assert.strictEqual(
      (provider as any).registerReplCallback,
      registerReplCallback,
    );
    assert.strictEqual(
      (provider as any).unregisterReplCallback,
      unregisterReplCallback,
    );
    assert.strictEqual(
      (provider as any).registerScratchPadCallback,
      registerScratchPadCallback,
    );
  });

  test("register registers commands and terminal profile providers", () => {
    provider = new RubyLspTerminalProfileProvider([mockWorkspace]);

    provider.register(mockContext);

    // Verify commands are registered
    assert.ok(registerCommandStub.calledWith("rubyLsp.createIrbTerminal"));
    assert.ok(
      registerCommandStub.calledWith("rubyLsp.createRailsConsoleTerminal"),
    );

    // Verify terminal profile providers are registered
    assert.ok(
      registerTerminalProfileProviderStub.calledWith("rubyLsp.irbTerminal"),
    );
    assert.ok(
      registerTerminalProfileProviderStub.calledWith(
        "rubyLsp.railsConsoleTerminal",
      ),
    );

    // Verify terminal open event listener is registered
    assert.ok(onDidOpenTerminalStub.called);
  });

  test("register only registers once", () => {
    provider = new RubyLspTerminalProfileProvider([mockWorkspace]);

    provider.register(mockContext);
    registerCommandStub.resetHistory();
    registerTerminalProfileProviderStub.resetHistory();

    provider.register(mockContext);

    assert.ok(registerCommandStub.notCalled);
    assert.ok(registerTerminalProfileProviderStub.notCalled);
  });

  test("dispose cleans up profile providers", () => {
    provider = new RubyLspTerminalProfileProvider([mockWorkspace]);

    const mockDisposable = { dispose: sandbox.stub() };
    (provider as any).irbProfileDisposable = mockDisposable;
    (provider as any).railsProfileDisposable = mockDisposable;

    provider.dispose();

    assert.ok(mockDisposable.dispose.calledTwice);
    assert.strictEqual((provider as any).irbProfileDisposable, undefined);
    assert.strictEqual((provider as any).railsProfileDisposable, undefined);
  });

  test("createIrbTerminal creates IRB terminal with workspace", async () => {
    provider = new RubyLspTerminalProfileProvider(
      [mockWorkspace],
      registerReplCallback,
      unregisterReplCallback,
      registerScratchPadCallback,
    );

    sandbox.stub(TerminalRepl.prototype, "start").resolves();
    sandbox.stub(TerminalRepl.prototype, "onDidClose");

    sandbox.stub(ReplScratchPad.prototype, "show").resolves();

    await (provider as any).createIrbTerminal();

    assert.ok(registerReplCallback.called);
  });

  test("createIrbTerminal shows error when no workspace found", async () => {
    provider = new RubyLspTerminalProfileProvider([]);

    await (provider as any).createIrbTerminal();

    assert.ok(
      (vscode.window.showErrorMessage as sinon.SinonStub).calledWith(
        "No Ruby workspace found",
      ),
    );
  });

  test("createRailsConsoleTerminal creates Rails console in Rails project", async () => {
    provider = new RubyLspTerminalProfileProvider(
      [mockWorkspace],
      registerReplCallback,
      unregisterReplCallback,
      registerScratchPadCallback,
    );

    // Mock Rails project detection
    sandbox.stub(provider as any, "isRailsProject").resolves(true);

    // Mock TerminalRepl
    sandbox.stub(TerminalRepl.prototype, "start").resolves();
    sandbox.stub(TerminalRepl.prototype, "onDidClose");

    // Mock ReplScratchPad
    sandbox.stub(ReplScratchPad.prototype, "show").resolves();

    await (provider as any).createRailsConsoleTerminal();

    assert.ok(registerReplCallback.called);
  });

  test("createRailsConsoleTerminal shows warning in non-Rails project", async () => {
    provider = new RubyLspTerminalProfileProvider([mockWorkspace]);

    // Mock non-Rails project
    sandbox.stub(provider as any, "isRailsProject").resolves(false);

    await (provider as any).createRailsConsoleTerminal();

    assert.ok(
      (vscode.window.showWarningMessage as sinon.SinonStub).calledWith(
        "Rails Console is only available in Rails projects. Use Ruby REPL instead.",
      ),
    );
  });

  test("provideIrbTerminalProfile returns IRB profile", async () => {
    provider = new RubyLspTerminalProfileProvider([mockWorkspace]);

    // Mock bundle exec detection
    sandbox.stub(provider as any, "shouldUseBundleExec").resolves(false);

    const token = {} as vscode.CancellationToken;
    const profile = await (provider as any).provideIrbTerminalProfile(token);

    assert.ok(profile);
    assert.strictEqual(profile.options.name, "Ruby REPL (IRB)");
    assert.strictEqual(
      profile.options.cwd,
      mockWorkspace.workspaceFolder.uri.fsPath,
    );
    assert.ok(
      profile.options.shellArgs[1].includes("irb --colorize --autocomplete"),
    );
  });

  test("provideIrbTerminalProfile uses bundle exec when Gemfile exists", async () => {
    provider = new RubyLspTerminalProfileProvider([mockWorkspace]);

    // Mock bundle exec detection
    sandbox.stub(provider as any, "shouldUseBundleExec").resolves(true);

    const token = {} as vscode.CancellationToken;
    const profile = await (provider as any).provideIrbTerminalProfile(token);

    assert.ok(
      profile.options.shellArgs[1].includes(
        "bundle exec irb --colorize --autocomplete",
      ),
    );
  });

  test("provideRailsConsoleTerminalProfile returns Rails profile for Rails project", async () => {
    provider = new RubyLspTerminalProfileProvider([mockWorkspace]);

    // Mock Rails project detection
    sandbox.stub(provider as any, "isRailsProject").resolves(true);
    sandbox.stub(provider as any, "shouldUseBundleExec").resolves(true);

    const token = {} as vscode.CancellationToken;
    const profile = await (provider as any).provideRailsConsoleTerminalProfile(
      token,
    );

    assert.ok(profile);
    assert.strictEqual(profile.options.name, "Rails Console");
    assert.ok(
      profile.options.shellArgs[1].includes("bundle exec rails console"),
    );
  });

  test("provideRailsConsoleTerminalProfile returns help message for non-Rails project", async () => {
    provider = new RubyLspTerminalProfileProvider([mockWorkspace]);

    // Mock non-Rails project
    sandbox.stub(provider as any, "isRailsProject").resolves(false);

    const token = {} as vscode.CancellationToken;
    const profile = await (provider as any).provideRailsConsoleTerminalProfile(
      token,
    );

    assert.ok(profile);
    assert.strictEqual(profile.options.name, "Rails Console");
    assert.ok(
      profile.options.shellArgs[1].includes("Rails Console is not available"),
    );
  });

  test("handleTerminalOpened wraps Ruby REPL terminal", async () => {
    provider = new RubyLspTerminalProfileProvider(
      [mockWorkspace],
      registerReplCallback,
      unregisterReplCallback,
    );

    const mockTerminal = { name: "Ruby REPL (IRB)" } as vscode.Terminal;

    // Mock wrapTerminalAsRepl
    const wrapSpy = sandbox
      .stub(provider as any, "wrapTerminalAsRepl")
      .resolves();

    await (provider as any).handleTerminalOpened(mockTerminal);

    assert.ok(wrapSpy.calledWith(mockTerminal, "irb"));
  });

  test("handleTerminalOpened wraps Rails Console terminal", async () => {
    provider = new RubyLspTerminalProfileProvider(
      [mockWorkspace],
      registerReplCallback,
      unregisterReplCallback,
    );

    const mockTerminal = { name: "Rails Console" } as vscode.Terminal;

    // Mock wrapTerminalAsRepl
    const wrapSpy = sandbox
      .stub(provider as any, "wrapTerminalAsRepl")
      .resolves();

    await (provider as any).handleTerminalOpened(mockTerminal);

    assert.ok(wrapSpy.calledWith(mockTerminal, "rails"));
  });

  test("handleTerminalOpened ignores other terminals", async () => {
    provider = new RubyLspTerminalProfileProvider([mockWorkspace]);

    const mockTerminal = { name: "Regular Terminal" } as vscode.Terminal;

    // Mock wrapTerminalAsRepl
    const wrapSpy = sandbox
      .stub(provider as any, "wrapTerminalAsRepl")
      .resolves();

    await (provider as any).handleTerminalOpened(mockTerminal);

    assert.ok(wrapSpy.notCalled);
  });

  test("getActiveWorkspace returns single workspace", () => {
    provider = new RubyLspTerminalProfileProvider([mockWorkspace]);

    const activeWorkspace = (provider as any).getActiveWorkspace();

    assert.strictEqual(activeWorkspace, mockWorkspace);
  });

  test("getActiveWorkspace returns workspace for active editor", () => {
    const secondWorkspace = {
      workspaceFolder: {
        uri: vscode.Uri.file("/test/workspace2"),
      },
    } as any;

    provider = new RubyLspTerminalProfileProvider([
      mockWorkspace,
      secondWorkspace,
    ]);

    // Mock active editor
    const mockEditor = {
      document: {
        uri: vscode.Uri.file("/test/workspace2/file.rb"),
      },
    };
    sandbox.stub(vscode.window, "activeTextEditor").value(mockEditor);
    getWorkspaceFolderStub.returns(secondWorkspace.workspaceFolder);

    const activeWorkspace = (provider as any).getActiveWorkspace();

    assert.strictEqual(activeWorkspace, secondWorkspace);
  });

  test("getActiveWorkspace falls back to first workspace", () => {
    const secondWorkspace = {
      workspaceFolder: {
        uri: vscode.Uri.file("/test/workspace2"),
      },
    } as any;

    provider = new RubyLspTerminalProfileProvider([
      mockWorkspace,
      secondWorkspace,
    ]);

    const activeWorkspace = (provider as any).getActiveWorkspace();

    assert.strictEqual(activeWorkspace, mockWorkspace);
  });

  test("isRailsProject returns true for Rails project with config/application.rb", async () => {
    provider = new RubyLspTerminalProfileProvider([mockWorkspace]);

    // Mock config/application.rb exists using sandbox.replaceGetter
    const originalFs = vscode.workspace.fs;
    const mockFs = {
      ...originalFs,
      stat: sinon.stub().onFirstCall().resolves(),
    };
    sandbox.replaceGetter(vscode.workspace, "fs", () => mockFs as any);

    const isRails = await (provider as any).isRailsProject(mockWorkspace);

    assert.strictEqual(isRails, true);
  });

  test("isRailsProject returns true for project with rails in Gemfile", async () => {
    provider = new RubyLspTerminalProfileProvider([mockWorkspace]);

    // Mock config/application.rb doesn't exist, but Gemfile has rails
    const originalFs = vscode.workspace.fs;
    const statStub = sinon.stub();
    const readFileStub = sinon.stub();

    // config/application.rb doesn't exist
    statStub.onFirstCall().rejects();
    // config/environment.rb doesn't exist
    statStub.onSecondCall().rejects();
    // Gemfile exists
    statStub.onThirdCall().resolves();

    readFileStub.resolves(new TextEncoder().encode('gem "rails"'));

    const mockFs = {
      ...originalFs,
      stat: statStub,
      readFile: readFileStub,
    };
    sandbox.replaceGetter(vscode.workspace, "fs", () => mockFs as any);

    const isRails = await (provider as any).isRailsProject(mockWorkspace);

    assert.strictEqual(isRails, true);
  });

  test("isRailsProject returns false for non-Rails project", async () => {
    provider = new RubyLspTerminalProfileProvider([mockWorkspace]);

    // Mock no Rails indicators found
    const originalFs = vscode.workspace.fs;
    const mockFs = {
      ...originalFs,
      stat: sinon.stub().rejects(),
    };
    sandbox.replaceGetter(vscode.workspace, "fs", () => mockFs as any);

    const isRails = await (provider as any).isRailsProject(mockWorkspace);

    assert.strictEqual(isRails, false);
  });

  test("shouldUseBundleExec returns true when Gemfile exists", async () => {
    provider = new RubyLspTerminalProfileProvider([mockWorkspace]);

    // Mock Gemfile exists
    const originalFs = vscode.workspace.fs;
    const mockFs = {
      ...originalFs,
      stat: sinon.stub().resolves(),
    };
    sandbox.replaceGetter(vscode.workspace, "fs", () => mockFs as any);

    const shouldUse = await (provider as any).shouldUseBundleExec(
      mockWorkspace,
    );

    assert.strictEqual(shouldUse, true);
  });

  test("shouldUseBundleExec returns false when Gemfile doesn't exist", async () => {
    provider = new RubyLspTerminalProfileProvider([mockWorkspace]);

    // Mock Gemfile doesn't exist
    const originalFs = vscode.workspace.fs;
    const mockFs = {
      ...originalFs,
      stat: sinon.stub().rejects(),
    };
    sandbox.replaceGetter(vscode.workspace, "fs", () => mockFs as any);

    const shouldUse = await (provider as any).shouldUseBundleExec(
      mockWorkspace,
    );

    assert.strictEqual(shouldUse, false);
  });

  test("autoOpenScratchPad reads configuration", () => {
    getConfigurationStub.returns({
      get: (key: string) => {
        if (key === "autoOpenScratchPad") return false;
        return undefined;
      },
    } as any);

    provider = new RubyLspTerminalProfileProvider([mockWorkspace]);

    const autoOpen = (provider as any).autoOpenScratchPad;

    assert.strictEqual(autoOpen, false);
    assert.ok(getConfigurationStub.calledWith("rubyLsp.replSettings"));
  });

  test("showWelcomeMessage reads configuration", () => {
    getConfigurationStub.returns({
      get: (key: string) => {
        if (key === "showWelcomeMessage") return false;
        return undefined;
      },
    } as any);

    provider = new RubyLspTerminalProfileProvider([mockWorkspace]);

    const showMessage = (provider as any).showWelcomeMessage;

    assert.strictEqual(showMessage, false);
    assert.ok(getConfigurationStub.calledWith("rubyLsp.replSettings"));
  });

  test("createAndShowScratchPad creates scratch pad when autoOpenScratchPad is true", async () => {
    provider = new RubyLspTerminalProfileProvider(
      [mockWorkspace],
      registerReplCallback,
      unregisterReplCallback,
      registerScratchPadCallback,
    );

    // Create mock terminal REPL instance
    const mockTerminalRepl = {} as TerminalRepl;

    // Mock ReplScratchPad show method
    const showSpy = sandbox.stub(ReplScratchPad.prototype, "show").resolves();

    // Call createAndShowScratchPad method
    await (provider as any).createAndShowScratchPad(
      mockTerminalRepl,
      "workspace1",
      "irb",
    );

    // Verify scratch pad was shown and callbacks were called
    assert.ok(showSpy.called);
    assert.ok(registerScratchPadCallback.called);

    // Verify welcome message was shown
    assert.ok(
      (vscode.window.showInformationMessage as sinon.SinonStub).calledWith(
        "Ruby REPL (IRB) started with scratch pad. Use Ctrl+Enter to execute code!",
      ),
    );
  });

  test("createAndShowScratchPad shows message when autoOpenScratchPad is false", async () => {
    // Mock autoOpenScratchPad to be false by restoring and recreating sandbox
    sandbox.restore();

    // Create new sandbox for this test
    sandbox = sinon.createSandbox();

    // Configure mocks for autoOpenScratchPad disabled
    sandbox.stub(vscode.workspace, "getConfiguration").returns({
      get: (key: string) => {
        if (key === "autoOpenScratchPad") return false;
        if (key === "showWelcomeMessage") return true;
        return undefined;
      },
    } as any);

    // Mock showInformationMessage
    sandbox.stub(vscode.window, "showInformationMessage");

    // Create provider instance with mocked configuration
    provider = new RubyLspTerminalProfileProvider([mockWorkspace]);

    // Create mock terminal REPL instance
    const mockTerminalRepl = {} as TerminalRepl;

    // Call createAndShowScratchPad method
    await (provider as any).createAndShowScratchPad(
      mockTerminalRepl,
      "workspace1",
      "irb",
    );

    // Verify success message is shown
    assert.ok(
      (vscode.window.showInformationMessage as sinon.SinonStub).calledWith(
        "Ruby REPL (IRB) started successfully",
      ),
    );
  });
});
