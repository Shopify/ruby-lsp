import * as vscode from "vscode";

import { VersionManager, ActivationResult } from "./versionManager";

// Manage your Ruby environment with rv
//
// Learn more: https://github.com/spinel-coop/rv
export class Rv extends VersionManager {
  async activate(): Promise<ActivationResult> {
    const rvExec = await this.findRv();
    const parsedResult = await this.runEnvActivationScript(`${rvExec} ruby run --`);

    return {
      env: { ...process.env, ...parsedResult.env },
      yjit: parsedResult.yjit,
      version: parsedResult.version,
      gemPath: parsedResult.gemPath,
    };
  }

  private async findRv(): Promise<string> {
    const config = vscode.workspace.getConfiguration("rubyLsp");
    const configuredRvPath = config.get<string | undefined>("rubyVersionManager.rvExecutablePath");

    if (configuredRvPath) {
      return this.ensureRvExistsAt(configuredRvPath);
    } else {
      const possiblePaths = [
        vscode.Uri.joinPath(vscode.Uri.file("/"), "home", "linuxbrew", ".linuxbrew", "bin"),
        vscode.Uri.joinPath(vscode.Uri.file("/"), "usr", "local", "bin"),
        vscode.Uri.joinPath(vscode.Uri.file("/"), "opt", "homebrew", "bin"),
        vscode.Uri.joinPath(vscode.Uri.file("/"), "usr", "bin"),
      ];
      return this.findExec(possiblePaths, "rv");
    }
  }

  private async ensureRvExistsAt(path: string): Promise<string> {
    try {
      await vscode.workspace.fs.stat(vscode.Uri.file(path));
      return path;
    } catch (_error: any) {
      throw new Error(`The Ruby LSP version manager is configured to be rv, but ${path} does not exist`);
    }
  }
}
