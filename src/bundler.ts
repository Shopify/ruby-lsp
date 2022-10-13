import { exec } from "child_process";
import { promisify } from "util";

import * as vscode from "vscode";

const asyncExec = promisify(exec);

export async function isGemOutdated(): Promise<boolean> {
  try {
    await execInPath("bundle outdated ruby-lsp");
  } catch {
    return true;
  }

  return false;
}

export async function updateGem(): Promise<void> {
  await execInPath("bundle update ruby-lsp --conservative");
}

async function execInPath(command: string): Promise<string> {
  const result = await asyncExec(command, {
    cwd: vscode.workspace.workspaceFolders![0].uri.fsPath,
  });

  return result.stdout;
}
