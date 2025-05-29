import * as vscode from "vscode";

import { Command } from "../common";
import { Workspace } from "../workspace";
import { TerminalRepl } from "../terminalRepl";

import { BaseCommandHandler } from "./commandHandler";

/**
 * Command handler for executing code in an existing REPL
 */
export class ExecInReplCommandHandler extends BaseCommandHandler {
  readonly commandId = Command.ExecInRepl;

  constructor(
    private currentActiveWorkspace: (
      activeEditor?: vscode.TextEditor,
    ) => Workspace | undefined,
    private getTerminalRepl: (workspaceKey: string) => TerminalRepl | undefined,
  ) {
    super();
  }

  async execute(): Promise<void> {
    const editor = this.getActiveEditor();
    if (!editor) {
      return;
    }

    const workspace = this.currentActiveWorkspace(editor);
    if (!workspace) {
      vscode.window.showWarningMessage("No workspace found for current file");
      return;
    }

    const workspaceKey = workspace.workspaceFolder.uri.toString();
    const terminalRepl = this.getTerminalRepl(workspaceKey);

    if (!terminalRepl || !terminalRepl.isRunning) {
      await this.promptToStartRepl();
      return;
    }

    const code = this.getCodeToExecute(editor);
    if (!code.trim()) {
      vscode.window.showWarningMessage("No code selected to execute");
      return;
    }

    try {
      await terminalRepl.execute(code);
    } catch (error) {
      this.showError("Failed to execute in REPL", error as Error);
    }
  }

  private getCodeToExecute(editor: vscode.TextEditor): string {
    const selection = editor.selection;

    if (selection.isEmpty) {
      return this.getCurrentLineText(editor);
    } else {
      return this.getSelectedText(editor);
    }
  }

  private getCurrentLineText(editor: vscode.TextEditor): string {
    const line = editor.document.lineAt(editor.selection.active.line);
    return line.text;
  }

  private getSelectedText(editor: vscode.TextEditor): string {
    return editor.document.getText(editor.selection);
  }

  private async promptToStartRepl(): Promise<void> {
    const answer = await vscode.window.showInformationMessage(
      "No REPL is running for this workspace. Would you like to start one?",
      "Start REPL",
    );

    if (answer === "Start REPL") {
      await vscode.commands.executeCommand(Command.StartRepl);
    }
  }
}
