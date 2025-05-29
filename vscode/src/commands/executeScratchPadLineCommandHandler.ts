import * as vscode from "vscode";

import { Command } from "../common";
import { ReplScratchPad } from "../replScratchPad";
import { TerminalRepl } from "../terminalRepl";

import { BaseScratchPadCommandHandler } from "./baseScratchPadCommandHandler";

/**
 * Command handler for executing the current line in a scratch pad
 */
export class ExecuteScratchPadLineCommandHandler extends BaseScratchPadCommandHandler {
  readonly commandId = Command.ExecuteScratchPadLine;

  protected async executeScratchPadAction(
    scratchPad: ReplScratchPad,
    terminalRepl: TerminalRepl,
    editor: vscode.TextEditor,
  ): Promise<void> {
    const code = scratchPad.getCurrentLineCode(editor);
    if (!this.isExecutableCode(code)) {
      scratchPad.moveCursorToNextLine(editor);
      return;
    }

    try {
      await terminalRepl.execute(code);
      scratchPad.showExecutionSuccess(editor, editor.selection.active.line);
    } catch (error) {
      this.showError("Failed to execute in scratch pad", error as Error);
      scratchPad.showExecutionError(
        editor,
        editor.selection.active.line,
        (error as Error).message,
      );
    }

    scratchPad.moveCursorToNextLine(editor);
  }
}
