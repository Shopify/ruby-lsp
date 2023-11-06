import fs from "fs/promises";
import { exec } from "child_process";
import { promisify } from "util";

import * as vscode from "vscode";

export const asyncExec = promisify(exec);
export const LOG_CHANNEL = vscode.window.createOutputChannel("Ruby LSP", {
  log: true,
});

export async function pathExists(
  path: string,
  mode = fs.constants.R_OK,
): Promise<boolean> {
  try {
    await fs.access(path, mode);
    return true;
  } catch (error: any) {
    return false;
  }
}
