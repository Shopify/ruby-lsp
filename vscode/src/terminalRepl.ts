import * as vscode from "vscode";

import { Workspace } from "./workspace";

export type ReplType = "irb" | "rails";

export class TerminalRepl implements vscode.Disposable {
  private terminal: vscode.Terminal | undefined;
  private readonly workspace: Workspace;
  private readonly replType: ReplType;
  private terminalCloseListener: vscode.Disposable | undefined;
  private onDidCloseCallback?: () => void;
  private wasSuccessfullyStarted = false;

  constructor(workspace: Workspace, replType: ReplType) {
    this.workspace = workspace;
    this.replType = replType;
  }

  async start(): Promise<void> {
    this.disposeExistingTerminal();
    this.terminal = this.createTerminalWithOptions();
    this.terminal.show();
    this.setupTerminalCloseListener();

    const replCommand = await this.buildReplCommand();

    this.sendReplCommandSafely(replCommand);
  }

  adoptTerminal(terminal: vscode.Terminal): void {
    this.disposeExistingTerminal();
    this.terminal = terminal;
    this.setupTerminalCloseListener();
  }

  async execute(code: string): Promise<void> {
    this.ensureTerminalExists();
    this.verifyTerminalIsActive();
    this.sendCodeToTerminal(code);
  }

  interrupt(): void {
    if (!this.terminal) {
      return;
    }

    if (!this.isTerminalActive()) {
      this.clearTerminalReference();
      return;
    }

    this.sendInterruptSignal();
  }

  dispose(): void {
    this.wasSuccessfullyStarted = false;
    this.disposeTerminalCloseListener();
    this.disposeTerminal();
  }

  get isRunning(): boolean {
    if (!this.terminal) {
      return false;
    }

    return vscode.window.terminals.includes(this.terminal);
  }

  onDidClose(callback: () => void): void {
    this.onDidCloseCallback = callback;
  }

  private disposeExistingTerminal(): void {
    if (this.terminal) {
      this.terminal.dispose();
    }
  }

  private createTerminalWithOptions(): vscode.Terminal {
    const terminalName = this.terminalName;
    const terminalOptions: vscode.TerminalOptions = {
      name: terminalName,
      cwd: this.workspace.workspaceFolder.uri.fsPath,
    };

    const terminal = vscode.window.createTerminal(terminalOptions);

    if (!terminal) {
      throw new Error(
        "Failed to create terminal - createTerminal returned null/undefined",
      );
    }

    return terminal;
  }

  private get terminalName(): string {
    return this.replType === "rails"
      ? "Rails Console (Direct)"
      : "Ruby REPL (IRB, Direct)";
  }

  private sendReplCommandSafely(replCommand: string): void {
    try {
      const terminal = this.getTerminalSafely();
      terminal.sendText(replCommand);
      this.wasSuccessfullyStarted = true;
    } catch (error) {
      this.handleReplCommandFailure(error);
    }
  }

  private handleReplCommandFailure(error: unknown): void {
    if (this.terminal) {
      this.terminal.dispose();
      this.terminal = undefined;
    }
    throw new Error(
      `Failed to send REPL command: ${error instanceof Error ? error.message : String(error)}`,
    );
  }

  private ensureTerminalExists(): void {
    if (!this.terminal) {
      throw new Error("REPL is not running");
    }
  }

  private verifyTerminalIsActive(): void {
    const terminal = this.getTerminalSafely();
    if (!vscode.window.terminals.includes(terminal)) {
      this.terminal = undefined;
      throw new Error("REPL terminal was closed");
    }
  }

  private sendCodeToTerminal(code: string): void {
    try {
      const terminal = this.getTerminalSafely();
      terminal.sendText(code);
    } catch (error) {
      this.terminal = undefined;
      throw new Error(`Failed to execute code in REPL: ${error}`);
    }
  }

  private isTerminalActive(): boolean {
    if (!this.terminal) {
      return false;
    }
    return vscode.window.terminals.includes(this.terminal);
  }

  private clearTerminalReference(): void {
    this.terminal = undefined;
  }

  private sendInterruptSignal(): void {
    if (!this.terminal) {
      return;
    }

    try {
      this.terminal.sendText("\x03", false);
    } catch (error) {
      this.terminal = undefined;
    }
  }

  private getTerminalSafely(): vscode.Terminal {
    if (!this.terminal) {
      throw new Error("Terminal is not available");
    }
    return this.terminal;
  }

  private disposeTerminalCloseListener(): void {
    if (this.terminalCloseListener) {
      this.terminalCloseListener.dispose();
      this.terminalCloseListener = undefined;
    }
  }

  private disposeTerminal(): void {
    if (this.terminal) {
      this.terminal.dispose();
      this.terminal = undefined;
    }
  }

  private setupTerminalCloseListener(): void {
    this.disposeTerminalCloseListener();
    this.terminalCloseListener = vscode.window.onDidCloseTerminal(
      this.handleTerminalClosed.bind(this),
    );
  }

  private handleTerminalClosed(closedTerminal: vscode.Terminal): void {
    if (this.isOurTerminal(closedTerminal)) {
      this.cleanupAfterTerminalClosed();
      this.notifyTerminalClosed();
      this.showTerminalClosedMessageIfAppropriate();
    }
  }

  private isOurTerminal(closedTerminal: vscode.Terminal): boolean {
    return closedTerminal === this.terminal;
  }

  private cleanupAfterTerminalClosed(): void {
    this.terminal = undefined;
    this.disposeTerminalCloseListener();
  }

  private notifyTerminalClosed(): void {
    if (this.onDidCloseCallback) {
      this.onDidCloseCallback();
    }
  }

  private showTerminalClosedMessageIfAppropriate(): void {
    if (this.wasSuccessfullyStarted) {
      const replName =
        this.replType === "rails" ? "Rails Console" : "Ruby REPL";
      vscode.window.showInformationMessage(`${replName} has been closed`);
    }
  }

  private async shouldUseBundleExec(): Promise<boolean> {
    try {
      await vscode.workspace.fs.stat(
        vscode.Uri.joinPath(this.workspace.workspaceFolder.uri, "Gemfile"),
      );
      return true;
    } catch {
      return false;
    }
  }

  private async buildReplCommand(): Promise<string> {
    const useBundle = await this.shouldUseBundleExec();

    if (this.replType === "rails") {
      return useBundle ? "bundle exec rails console" : "rails console";
    } else {
      const irbOptions = "--colorize --autocomplete";
      return useBundle ? `bundle exec irb ${irbOptions}` : `irb ${irbOptions}`;
    }
  }
}
