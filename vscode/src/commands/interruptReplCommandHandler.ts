import * as vscode from "vscode";

import { Command } from "../common";
import { Workspace } from "../workspace";
import { TerminalRepl } from "../terminalRepl";

import { BaseCommandHandler } from "./commandHandler";

/**
 * Command handler for interrupting a running REPL session
 */
export class InterruptReplCommandHandler extends BaseCommandHandler {
  readonly commandId = Command.InterruptRepl;

  constructor(
    private showWorkspacePick: () => Promise<Workspace | undefined>,
    private getTerminalRepl: (workspaceKey: string) => TerminalRepl | undefined,
  ) {
    super();
  }

  async execute(): Promise<void> {
    const workspace = await this.showWorkspacePick();
    if (!workspace) {
      return;
    }

    const workspaceKey = workspace.workspaceFolder.uri.toString();
    const terminalRepl = this.getTerminalRepl(workspaceKey);

    if (!terminalRepl || !terminalRepl.isRunning) {
      vscode.window.showInformationMessage(
        "No REPL is running for this workspace",
      );
      return;
    }

    terminalRepl.interrupt();
    vscode.window.showInformationMessage("REPL interrupted");
  }
}
