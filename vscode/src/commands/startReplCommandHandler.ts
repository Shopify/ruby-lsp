import * as vscode from "vscode";

import { Command } from "../common";
import { Workspace } from "../workspace";
import { ReplType } from "../terminalRepl";

import { BaseCommandHandler } from "./commandHandler";

/**
 * Command handler for starting a new REPL session
 */
export class StartReplCommandHandler extends BaseCommandHandler {
  readonly commandId = Command.StartRepl;

  constructor(
    private showWorkspacePick: () => Promise<Workspace | undefined>,
    private startRepl: (
      workspace: Workspace,
      replType: ReplType,
    ) => Promise<void>,
  ) {
    super();
  }

  async execute(): Promise<void> {
    const workspace = await this.showWorkspacePick();
    if (!workspace) {
      return;
    }

    const replType = await this.selectReplType();
    if (!replType) {
      return;
    }

    try {
      await this.startRepl(workspace, replType);
    } catch (error) {
      this.showError("Failed to start REPL", error as Error);
    }
  }

  private async selectReplType(): Promise<ReplType | undefined> {
    const replType = await vscode.window.showQuickPick(["irb", "rails"], {
      placeHolder: "Select REPL type",
    });

    return replType as ReplType | undefined;
  }
}
