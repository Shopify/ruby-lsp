import * as vscode from "vscode";

import { Command } from "../common";
import { ReplScratchPad } from "../replScratchPad";
import { TerminalRepl } from "../terminalRepl";

import { BaseScratchPadCommandHandler } from "./baseScratchPadCommandHandler";

/**
 * Command handler for executing the selected text in a scratch pad
 */
export class ExecuteScratchPadSelectionCommandHandler extends BaseScratchPadCommandHandler {
  readonly commandId = Command.ExecuteScratchPadSelection;

  protected async executeScratchPadAction(
    scratchPad: ReplScratchPad,
    terminalRepl: TerminalRepl,
    editor: vscode.TextEditor,
  ): Promise<void> {
    const { code, lineNumber } = scratchPad.getSelectionCode(editor);
    if (!this.isExecutableCode(code)) {
      return;
    }

    try {
      await terminalRepl.execute(code);
      scratchPad.showExecutionSuccess(editor, lineNumber);
    } catch (error) {
      this.showError("Failed to execute in scratch pad", error as Error);
      scratchPad.showExecutionError(
        editor,
        lineNumber,
        (error as Error).message,
      );
    }
  }
}
