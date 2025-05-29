import * as vscode from "vscode";

import { Workspace } from "../workspace";
import { ReplScratchPad } from "../replScratchPad";
import { TerminalRepl } from "../terminalRepl";

import { BaseCommandHandler } from "./commandHandler";

/**
 * Base class for scratch pad execution commands
 */
export abstract class BaseScratchPadCommandHandler extends BaseCommandHandler {
  constructor(
    private currentActiveWorkspace: (
      activeEditor?: vscode.TextEditor,
    ) => Workspace | undefined,
    private getScratchPad: (workspaceKey: string) => ReplScratchPad | undefined,
    private getTerminalRepl: (workspaceKey: string) => TerminalRepl | undefined,
  ) {
    super();
  }

  async execute(): Promise<void> {
    const editor = this.getActiveEditor();
    if (!editor) {
      return;
    }

    if (!this.isScratchPadDocument(editor.document)) {
      return;
    }

    const workspace = this.currentActiveWorkspace(editor);
    if (!workspace) {
      return;
    }

    const workspaceKey = workspace.workspaceFolder.uri.toString();
    const scratchPad = this.getScratchPad(workspaceKey);

    if (!scratchPad) {
      vscode.window.showWarningMessage(
        "No scratch pad found for this workspace",
      );
      return;
    }

    const terminalRepl = this.getTerminalRepl(workspaceKey);
    if (!terminalRepl) {
      vscode.window.showWarningMessage("No REPL found for this workspace");
      return;
    }

    await this.executeScratchPadAction(scratchPad, terminalRepl, editor);
  }

  protected abstract executeScratchPadAction(
    scratchPad: ReplScratchPad,
    terminalRepl: TerminalRepl,
    editor: vscode.TextEditor,
  ): Promise<void>;

  protected isExecutableCode(code: string): boolean {
    return Boolean(code && !code.startsWith("#"));
  }

  private isScratchPadDocument(document: vscode.TextDocument): boolean {
    return document.isUntitled && document.languageId === "ruby";
  }
}
