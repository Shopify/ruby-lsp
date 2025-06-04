import * as vscode from "vscode";

import { TerminalRepl, ReplType } from "./terminalRepl";
import { ReplScratchPad } from "./replScratchPad";
import { Workspace } from "./workspace";
import { Command } from "./common";

export class RubyLspTerminalProfileProvider {
  private workspaces: Workspace[];
  private registered = false;
  private registerReplCallback?: (
    workspaceKey: string,
    repl: TerminalRepl,
  ) => void;

  private unregisterReplCallback?: (workspaceKey: string) => void;
  private registerScratchPadCallback?: (
    workspaceKey: string,
    scratchPad: ReplScratchPad,
  ) => void;

  private irbProfileDisposable?: vscode.Disposable;
  private railsProfileDisposable?: vscode.Disposable;

  constructor(
    workspaces: Workspace[],
    registerReplCallback?: (workspaceKey: string, repl: TerminalRepl) => void,
    unregisterReplCallback?: (workspaceKey: string) => void,
    registerScratchPadCallback?: (
      workspaceKey: string,
      scratchPad: ReplScratchPad,
    ) => void,
  ) {
    this.workspaces = workspaces;
    this.registerReplCallback = registerReplCallback;
    this.unregisterReplCallback = unregisterReplCallback;
    this.registerScratchPadCallback = registerScratchPadCallback;
  }

  public async updateWorkspaces(workspaces: Workspace[]): Promise<void> {
    this.workspaces = workspaces;
  }

  public setCallbacks(
    registerReplCallback: (workspaceKey: string, repl: TerminalRepl) => void,
    unregisterReplCallback: (workspaceKey: string) => void,
    registerScratchPadCallback?: (
      workspaceKey: string,
      scratchPad: ReplScratchPad,
    ) => void,
  ): void {
    this.registerReplCallback = registerReplCallback;
    this.unregisterReplCallback = unregisterReplCallback;
    this.registerScratchPadCallback = registerScratchPadCallback;
  }

  public dispose(): void {
    this.disposeProfileProviders();
  }

  public register(context: vscode.ExtensionContext): void {
    if (this.registered) {
      return;
    }

    this.registerCommands(context);
    this.registerTerminalProfileProviders(context);
    this.setupTerminalMonitoring(context);

    this.registered = true;
  }

  private disposeProfileProviders(): void {
    if (this.irbProfileDisposable) {
      this.irbProfileDisposable.dispose();
      this.irbProfileDisposable = undefined;
    }

    if (this.railsProfileDisposable) {
      this.railsProfileDisposable.dispose();
      this.railsProfileDisposable = undefined;
    }
  }

  private registerCommands(context: vscode.ExtensionContext): void {
    context.subscriptions.push(
      vscode.commands.registerCommand(Command.CreateIrbTerminal, () =>
        this.createIrbTerminal(),
      ),
      vscode.commands.registerCommand(Command.CreateRailsConsoleTerminal, () =>
        this.createRailsConsoleTerminal(),
      ),
    );
  }

  private registerTerminalProfileProviders(
    context: vscode.ExtensionContext,
  ): void {
    this.irbProfileDisposable = vscode.window.registerTerminalProfileProvider(
      "rubyLsp.irbTerminal",
      {
        provideTerminalProfile: (
          token: vscode.CancellationToken,
        ): vscode.ProviderResult<vscode.TerminalProfile> => {
          return this.provideIrbTerminalProfile(token);
        },
      },
    );
    context.subscriptions.push(this.irbProfileDisposable);

    this.railsProfileDisposable = vscode.window.registerTerminalProfileProvider(
      "rubyLsp.railsConsoleTerminal",
      {
        provideTerminalProfile: (
          token: vscode.CancellationToken,
        ): vscode.ProviderResult<vscode.TerminalProfile> => {
          return this.provideRailsConsoleTerminalProfile(token);
        },
      },
    );
    context.subscriptions.push(this.railsProfileDisposable);
  }

  private setupTerminalMonitoring(context: vscode.ExtensionContext): void {
    context.subscriptions.push(
      vscode.window.onDidOpenTerminal((terminal) => {
        this.handleTerminalOpened(terminal).catch(() => {});
      }),
    );
  }

  private async handleTerminalOpened(terminal: vscode.Terminal): Promise<void> {
    if (this.isReplTerminal(terminal)) {
      const replType = terminal.name === "Rails Console" ? "rails" : "irb";
      await this.wrapTerminalAsRepl(terminal, replType);
    }
  }

  private isReplTerminal(terminal: vscode.Terminal): boolean {
    return (
      terminal.name === "Ruby REPL (IRB)" || terminal.name === "Rails Console"
    );
  }

  private async wrapTerminalAsRepl(
    terminal: vscode.Terminal,
    replType: ReplType,
  ): Promise<void> {
    const workspace = this.getActiveWorkspace();
    if (!workspace) {
      return;
    }

    const workspaceKey = workspace.workspaceFolder.uri.toString();

    this.unregisterExistingRepl(workspaceKey);

    const terminalRepl = new TerminalRepl(workspace, replType);
    terminalRepl.adoptTerminal(terminal);

    terminalRepl.onDidClose(() => {
      this.unregisterExistingRepl(workspaceKey);
    });

    this.registerNewRepl(workspaceKey, terminalRepl);
    await this.createAndShowScratchPad(workspaceKey, replType);
  }

  private async createIrbTerminal(): Promise<void> {
    const workspace = this.getActiveWorkspace();
    if (!workspace) {
      vscode.window.showErrorMessage("No Ruby workspace found");
      return;
    }

    const workspaceKey = workspace.workspaceFolder.uri.toString();
    this.unregisterExistingRepl(workspaceKey);

    const terminalRepl = new TerminalRepl(workspace, "irb");
    terminalRepl.onDidClose(() => {
      this.unregisterExistingRepl(workspaceKey);
    });

    this.registerNewRepl(workspaceKey, terminalRepl);

    try {
      await terminalRepl.start();
      await this.createAndShowScratchPad(workspaceKey, "irb");
    } catch (error: any) {
      this.handleReplStartFailure("IRB", error, workspaceKey, terminalRepl);
    }
  }

  private async createRailsConsoleTerminal(): Promise<void> {
    const workspace = this.getActiveWorkspace();
    if (!workspace) {
      vscode.window.showErrorMessage("No Ruby workspace found");
      return;
    }

    if (!(await this.isRailsProject(workspace))) {
      this.showNonRailsProjectWarning();
      return;
    }

    const workspaceKey = workspace.workspaceFolder.uri.toString();
    this.unregisterExistingRepl(workspaceKey);

    const terminalRepl = new TerminalRepl(workspace, "rails");
    terminalRepl.onDidClose(() => {
      this.unregisterExistingRepl(workspaceKey);
    });

    this.registerNewRepl(workspaceKey, terminalRepl);

    try {
      await terminalRepl.start();
      await this.createAndShowScratchPad(workspaceKey, "rails");
    } catch (error: any) {
      this.handleReplStartFailure(
        "Rails Console",
        error,
        workspaceKey,
        terminalRepl,
      );
    }
  }

  private unregisterExistingRepl(workspaceKey: string): void {
    if (this.unregisterReplCallback) {
      this.unregisterReplCallback(workspaceKey);
    }
  }

  private registerNewRepl(
    workspaceKey: string,
    terminalRepl: TerminalRepl,
  ): void {
    if (this.registerReplCallback) {
      this.registerReplCallback(workspaceKey, terminalRepl);
    }
  }

  private showNonRailsProjectWarning(): void {
    vscode.window.showWarningMessage(
      "Rails Console is only available in Rails projects. Use Ruby REPL instead.",
    );
  }

  private handleReplStartFailure(
    replName: string,
    error: any,
    workspaceKey: string,
    terminalRepl: TerminalRepl,
  ): void {
    vscode.window.showErrorMessage(
      `Failed to start ${replName}: ${error.message}`,
    );
    terminalRepl.dispose();
    this.unregisterExistingRepl(workspaceKey);
  }

  private async provideIrbTerminalProfile(
    _token: vscode.CancellationToken,
  ): Promise<vscode.TerminalProfile | undefined> {
    const workspace = this.getActiveWorkspace();
    if (!workspace) {
      return undefined;
    }

    const irbCommand = await this.buildIrbCommand(workspace);

    return {
      options: {
        name: "Ruby REPL (IRB)",
        cwd: workspace.workspaceFolder.uri.fsPath,
        env: this.buildIrbEnvironment(workspace),
        iconPath: new vscode.ThemeIcon("ruby"),
        isTransient: true,
        shellPath: "/bin/sh",
        shellArgs: ["-c", `${irbCommand} && exit`],
      },
    };
  }

  private async buildIrbCommand(workspace: Workspace): Promise<string> {
    const useBundle = await this.shouldUseBundleExec(workspace);
    const irbOptions = "--colorize --autocomplete";
    return useBundle ? `bundle exec irb ${irbOptions}` : `irb ${irbOptions}`;
  }

  private buildIrbEnvironment(workspace: Workspace): Record<string, string> {
    return {
      ...workspace.ruby.env,
      TERM: "xterm-256color",
      COLORTERM: "truecolor",
      IRBRC: "",
      IRB_USE_COLORIZE: "true",
    };
  }

  private async provideRailsConsoleTerminalProfile(
    _token: vscode.CancellationToken,
  ): Promise<vscode.TerminalProfile | undefined> {
    const workspace = this.getActiveWorkspace();
    if (!workspace) {
      return undefined;
    }

    if (!(await this.isRailsProject(workspace))) {
      return this.createNonRailsHelpProfile(workspace);
    }

    const railsCommand = await this.buildRailsCommand(workspace);

    return {
      options: {
        name: "Rails Console",
        cwd: workspace.workspaceFolder.uri.fsPath,
        env: this.buildRailsEnvironment(workspace),
        iconPath: new vscode.ThemeIcon("ruby"),
        isTransient: true,
        shellPath: "/bin/sh",
        shellArgs: ["-c", `${railsCommand} && exit`],
      },
    };
  }

  private createNonRailsHelpProfile(
    workspace: Workspace,
  ): vscode.TerminalProfile {
    const helpMessage = [
      'echo "❌ Rails Console is not available in this project."',
      'echo ""',
      'echo "This doesn\'t appear to be a Rails project."',
      'echo "Try using \\"Ruby REPL (IRB)\\" instead!"',
      'echo ""',
      'echo "Press any key to close..."',
      "read -n 1",
      "exit",
    ].join("; ");

    return {
      options: {
        name: "Rails Console",
        cwd: workspace.workspaceFolder.uri.fsPath,
        env: workspace.ruby.env,
        iconPath: new vscode.ThemeIcon("ruby"),
        isTransient: true,
        shellPath: "/bin/sh",
        shellArgs: ["-c", helpMessage],
      },
    };
  }

  private async buildRailsCommand(workspace: Workspace): Promise<string> {
    const useBundle = await this.shouldUseBundleExec(workspace);
    return useBundle ? "bundle exec rails console" : "rails console";
  }

  private buildRailsEnvironment(workspace: Workspace): Record<string, string> {
    return {
      ...workspace.ruby.env,
      TERM: "xterm-256color",
      COLORTERM: "truecolor",
    };
  }

  private getActiveWorkspace(): Workspace | undefined {
    if (this.workspaces.length === 1) {
      return this.workspaces[0];
    }

    const workspaceForActiveEditor = this.findWorkspaceForActiveEditor();
    return workspaceForActiveEditor || this.workspaces[0];
  }

  private findWorkspaceForActiveEditor(): Workspace | undefined {
    const activeEditor = vscode.window.activeTextEditor;
    if (!activeEditor) {
      return undefined;
    }

    const activeWorkspaceFolder = vscode.workspace.getWorkspaceFolder(
      activeEditor.document.uri,
    );
    if (!activeWorkspaceFolder) {
      return undefined;
    }

    return this.workspaces.find(
      (ws) =>
        ws.workspaceFolder.uri.toString() ===
        activeWorkspaceFolder.uri.toString(),
    );
  }

  private async isRailsProject(workspace: Workspace): Promise<boolean> {
    if (await this.hasRailsConfigFile(workspace)) {
      return true;
    }

    return this.hasRailsInGemfile(workspace);
  }

  private async hasRailsConfigFile(workspace: Workspace): Promise<boolean> {
    try {
      const configFile = vscode.Uri.joinPath(
        workspace.workspaceFolder.uri,
        "config",
        "application.rb",
      );
      await vscode.workspace.fs.stat(configFile);
      return true;
    } catch {
      return false;
    }
  }

  private async hasRailsInGemfile(workspace: Workspace): Promise<boolean> {
    try {
      const gemfileUri = vscode.Uri.joinPath(
        workspace.workspaceFolder.uri,
        "Gemfile",
      );
      const gemfileContent = await vscode.workspace.fs.readFile(gemfileUri);
      const content = new TextDecoder().decode(gemfileContent);
      return (
        content.includes("rails") ||
        content.includes("'rails'") ||
        content.includes('"rails"')
      );
    } catch {
      return false;
    }
  }

  private async shouldUseBundleExec(workspace: Workspace): Promise<boolean> {
    try {
      await vscode.workspace.fs.stat(
        vscode.Uri.joinPath(workspace.workspaceFolder.uri, "Gemfile"),
      );
      return true;
    } catch {
      return false;
    }
  }

  private get autoOpenScratchPad(): boolean {
    const config = vscode.workspace.getConfiguration("rubyLsp.replSettings");
    return config.get<boolean>("autoOpenScratchPad")!;
  }

  private get showWelcomeMessage(): boolean {
    const config = vscode.workspace.getConfiguration("rubyLsp.replSettings");
    return config.get<boolean>("showWelcomeMessage")!;
  }

  private async createAndShowScratchPad(
    workspaceKey: string,
    replType: ReplType,
  ): Promise<void> {
    if (!this.autoOpenScratchPad || !this.registerScratchPadCallback) {
      this.showReplStartedMessage(replType);
      return;
    }

    const scratchPad = new ReplScratchPad();
    this.registerScratchPadCallback(workspaceKey, scratchPad);
    await scratchPad.show();
    this.showScratchPadStartedMessage(replType);
  }

  private showReplStartedMessage(replType: ReplType): void {
    if (this.showWelcomeMessage) {
      const replTypeName = this.getReplDisplayName(replType);
      vscode.window.showInformationMessage(
        `${replTypeName} started successfully`,
      );
    }
  }

  private showScratchPadStartedMessage(replType: ReplType): void {
    if (this.showWelcomeMessage) {
      const replTypeName = this.getReplDisplayName(replType);
      vscode.window.showInformationMessage(
        `${replTypeName} started with scratch pad. Use Ctrl+Enter to execute code!`,
      );
    }
  }

  private getReplDisplayName(replType: ReplType): string {
    return replType === "rails" ? "Rails Console" : "Ruby REPL (IRB)";
  }
}
