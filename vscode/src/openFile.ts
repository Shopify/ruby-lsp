import * as vscode from "vscode";

import { Telemetry } from "./telemetry";
import { Workspace } from "./workspace";

interface SourceLocation {
  file: string;
  line: number;
  character?: number;
  endLine?: number;
  endCharacter?: number;
}

export async function openFile(
  telemetry: Telemetry,
  workspace: Workspace | undefined,
  sourceLocation: SourceLocation,
) {
  const { file, ...location } = sourceLocation;
  const {
    line,
    character = 0,
    endLine = line,
    endCharacter = character,
  } = location;
  const selection = new vscode.Range(line, character, endLine, endCharacter);
  const uri = vscode.Uri.parse(`file://${file}`);
  const doc = await vscode.workspace.openTextDocument(uri);

  await vscode.window.showTextDocument(doc, { selection });

  if (workspace?.lspClient?.serverVersion) {
    await telemetry.sendCodeLensEvent(
      "open_file",
      workspace.lspClient.serverVersion,
    );
  }
}
