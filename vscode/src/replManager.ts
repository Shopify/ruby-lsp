import * as vscode from "vscode";

import { TerminalRepl, ReplType } from "./terminalRepl";
import { ReplScratchPad } from "./replScratchPad";
import { RubyLspTerminalProfileProvider } from "./terminalProfileProvider";
import { Workspace } from "./workspace";
import { CommandHandler } from "./commands/commandHandler";
import { StartReplCommandHandler } from "./commands/startReplCommandHandler";
import { ExecInReplCommandHandler } from "./commands/execInReplCommandHandler";
import { InterruptReplCommandHandler } from "./commands/interruptReplCommandHandler";
import { ExecuteScratchPadLineCommandHandler } from "./commands/executeScratchPadLineCommandHandler";
import { ExecuteScratchPadSelectionCommandHandler } from "./commands/executeScratchPadSelectionCommandHandler";

export class ReplManager implements vscode.Disposable {
  private terminalRepls: Map<string, TerminalRepl> = new Map();
  private replScratchPads: Map<string, ReplScratchPad> = new Map();
  private terminalProfileProvider: RubyLspTerminalProfileProvider;
  private commandHandlers: CommandHandler[] = [];

  constructor(
    private context: vscode.ExtensionContext,
    private getWorkspaces: () => Workspace[],
    private showWorkspacePick: () => Promise<Workspace | undefined>,
    private currentActiveWorkspace: (
      activeEditor?: vscode.TextEditor,
    ) => Workspace | undefined,
  ) {
    this.terminalProfileProvider = new RubyLspTerminalProfileProvider(
      [],
      this.registerRepl.bind(this),
      this.unregisterRepl.bind(this),
      this.registerScratchPad.bind(this),
    );

    this.initializeCommandHandlers();
  }

  public register(): vscode.Disposable[] {
    this.terminalProfileProvider.register(this.context);

    return this.commandHandlers.map((handler) => handler.register());
  }

  public async updateWorkspaces(): Promise<void> {
    await this.terminalProfileProvider.updateWorkspaces(this.getWorkspaces());
  }

  public dispose(): void {
    this.disposeAllTerminalRepls();
    this.disposeAllScratchPads();
    this.terminalProfileProvider.dispose();
  }

  private disposeAllTerminalRepls(): void {
    for (const terminalRepl of this.terminalRepls.values()) {
      terminalRepl.dispose();
    }
    this.terminalRepls.clear();
  }

  private disposeAllScratchPads(): void {
    for (const scratchPad of this.replScratchPads.values()) {
      scratchPad.dispose();
    }
    this.replScratchPads.clear();
  }

  private initializeCommandHandlers(): void {
    this.commandHandlers = [
      new StartReplCommandHandler(
        this.showWorkspacePick,
        this.startRepl.bind(this),
      ),
      new ExecInReplCommandHandler(
        this.currentActiveWorkspace,
        (workspaceKey: string) => this.terminalRepls.get(workspaceKey),
      ),
      new InterruptReplCommandHandler(
        this.showWorkspacePick,
        (workspaceKey: string) => this.terminalRepls.get(workspaceKey),
      ),
      new ExecuteScratchPadLineCommandHandler(
        this.currentActiveWorkspace,
        (workspaceKey: string) => this.replScratchPads.get(workspaceKey),
        (workspaceKey: string) => this.terminalRepls.get(workspaceKey),
      ),
      new ExecuteScratchPadSelectionCommandHandler(
        this.currentActiveWorkspace,
        (workspaceKey: string) => this.replScratchPads.get(workspaceKey),
        (workspaceKey: string) => this.terminalRepls.get(workspaceKey),
      ),
    ];
  }

  private async startRepl(
    workspace: Workspace,
    replType: ReplType,
  ): Promise<void> {
    const workspaceKey = workspace.workspaceFolder.uri.toString();

    this.cleanupExistingReplForWorkspace(workspaceKey);
    const terminalRepl = this.createTerminalRepl(
      workspace,
      replType,
      workspaceKey,
    );

    try {
      await terminalRepl.start();
      await this.handleSuccessfulReplStart(workspaceKey, replType);
    } catch (error: any) {
      this.handleReplStartFailure(workspaceKey, terminalRepl, error);
    }
  }

  private cleanupExistingReplForWorkspace(workspaceKey: string): void {
    const existingRepl = this.terminalRepls.get(workspaceKey);
    if (existingRepl) {
      existingRepl.dispose();
      this.terminalRepls.delete(workspaceKey);
    }
  }

  private createTerminalRepl(
    workspace: Workspace,
    replType: ReplType,
    workspaceKey: string,
  ): TerminalRepl {
    const terminalRepl = new TerminalRepl(workspace, replType);

    terminalRepl.onDidClose(() => {
      this.cleanupWorkspaceResources(workspaceKey);
    });

    this.terminalRepls.set(workspaceKey, terminalRepl);
    return terminalRepl;
  }

  private cleanupWorkspaceResources(workspaceKey: string): void {
    this.terminalRepls.delete(workspaceKey);
    this.disposeScratchPadForWorkspace(workspaceKey);
  }

  private async handleSuccessfulReplStart(
    workspaceKey: string,
    replType: ReplType,
  ): Promise<void> {
    if (this.autoOpenScratchPad) {
      await this.createAndShowScratchPad(workspaceKey);
      this.showScratchPadWelcomeMessage();
    } else if (this.showWelcomeMessage) {
      this.showReplWelcomeMessage(replType);
    }
  }

  private async createAndShowScratchPad(workspaceKey: string): Promise<void> {
    const scratchPad = new ReplScratchPad();
    this.replScratchPads.set(workspaceKey, scratchPad);
    await scratchPad.show();
  }

  private showScratchPadWelcomeMessage(): void {
    if (this.showWelcomeMessage) {
      vscode.window.showInformationMessage(
        "Ruby REPL started with scratch pad. Use Ctrl+Enter to execute code!",
      );
    }
  }

  private showReplWelcomeMessage(replType: ReplType): void {
    vscode.window.showInformationMessage(
      `${replType === "rails" ? "Rails Console" : "Ruby REPL"} started successfully`,
    );
  }

  private handleReplStartFailure(
    workspaceKey: string,
    terminalRepl: TerminalRepl,
    error: any,
  ): void {
    vscode.window.showErrorMessage(`Failed to start REPL: ${error.message}`);
    terminalRepl.dispose();
    this.terminalRepls.delete(workspaceKey);
  }

  private getReplSettings(): vscode.WorkspaceConfiguration {
    return vscode.workspace.getConfiguration("rubyLsp.replSettings");
  }

  private getReplSetting<T>(key: string): T {
    return this.getReplSettings().get<T>(key)!;
  }

  private get autoOpenScratchPad(): boolean {
    return this.getReplSetting<boolean>("autoOpenScratchPad");
  }

  private get showWelcomeMessage(): boolean {
    return this.getReplSetting<boolean>("showWelcomeMessage");
  }

  private registerRepl(workspaceKey: string, repl: TerminalRepl): void {
    this.disposeReplForWorkspace(workspaceKey);
    this.terminalRepls.set(workspaceKey, repl);
    this.disposeScratchPadForWorkspace(workspaceKey);
  }

  private unregisterRepl(workspaceKey: string): void {
    this.disposeReplForWorkspace(workspaceKey);
    this.disposeScratchPadForWorkspace(workspaceKey);
  }

  private disposeReplForWorkspace(workspaceKey: string): void {
    const terminalRepl = this.terminalRepls.get(workspaceKey);
    if (terminalRepl) {
      terminalRepl.dispose();
      this.terminalRepls.delete(workspaceKey);
    }
  }

  private disposeScratchPadForWorkspace(workspaceKey: string): void {
    const scratchPad = this.replScratchPads.get(workspaceKey);
    if (scratchPad) {
      scratchPad.dispose();
      this.replScratchPads.delete(workspaceKey);
    }
  }

  private registerScratchPad(
    workspaceKey: string,
    scratchPad: ReplScratchPad,
  ): void {
    this.disposeScratchPadForWorkspace(workspaceKey);
    this.replScratchPads.set(workspaceKey, scratchPad);
  }
}
