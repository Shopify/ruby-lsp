import { exec } from "child_process";
import { promisify } from "util";

import * as vscode from "vscode";

const asyncExec = promisify(exec);

export async function isGemMissing(): Promise<boolean> {
  try {
    await execInPath("bundle show ruby-lsp");
    return false;
  } catch {
    return true;
  }
}

export async function isGemOutdated(): Promise<boolean> {
  try {
    await execInPath("bundle outdated ruby-lsp");
  } catch {
    return true;
  }

  return false;
}

export async function addGem(): Promise<void> {
  await execInPath(
    "bundle add ruby-lsp --group=development --require=false && bundle install"
  );
}

export async function updateGem(): Promise<{ stdout: string; stderr: string }> {
  return execInPath("bundle update ruby-lsp");
}

export async function bundleCheck(): Promise<boolean> {
  try {
    await execInPath("bundle check");
    return true;
  } catch {
    return false;
  }
}

export async function bundleInstall(): Promise<{
  stdout: string;
  stderr: string;
}> {
  return execInPath("bundle install");
}

async function execInPath(
  command: string
): Promise<{ stdout: string; stderr: string }> {
  return asyncExec(command, {
    cwd: vscode.workspace.workspaceFolders![0].uri.fsPath,
  });
}
