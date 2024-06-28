import * as vscode from "vscode";

import { Telemetry } from "./telemetry";
import { Workspace } from "./workspace";

export class FileController {
  private readonly telemetry: Telemetry;
  private readonly currentWorkspace: () => Workspace | undefined;

  constructor(
    _context: vscode.ExtensionContext,
    telemetry: Telemetry,
    currentWorkspace: () => Workspace | undefined,
  ) {
    this.telemetry = telemetry;
    this.currentWorkspace = currentWorkspace;
  }

  async openFile(sourceLocation: [string, string]) {
    const workspace = this.currentWorkspace();
    const file = sourceLocation[0];
    const line = parseInt(sourceLocation[1], 10) - 1;

    const uri = vscode.Uri.parse(`file://${file}`);
    const doc = await vscode.workspace.openTextDocument(uri);
    await vscode.window.showTextDocument(doc, {
      selection: new vscode.Range(line, 0, line, 0),
    });

    if (workspace?.lspClient?.serverVersion) {
      await this.telemetry.sendCodeLensEvent(
        "open_file",
        workspace.lspClient.serverVersion,
      );
    }
  }
}
