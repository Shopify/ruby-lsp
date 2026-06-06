import os from "os";

import * as vscode from "vscode";

import { VersionManager, ActivationResult, NonReportableError } from "./versionManager";

// Mise (mise en place) is a manager for dev tools, environment variables and tasks
//
// Learn more: https://github.com/jdx/mise
export class Mise extends VersionManager {
  async activate(): Promise<ActivationResult> {
    const miseExec = await this.findMise();

    // The exec command in Mise is called `x`
    const parsedResult = await this.runEnvActivationScript(`${miseExec} x -- ruby`);

    return {
      env: { ...process.env, ...parsedResult.env },
      yjit: parsedResult.yjit,
      version: parsedResult.version,
      gemPath: parsedResult.gemPath,
    };
  }

  async findMise(): Promise<string> {
    const config = vscode.workspace.getConfiguration("rubyLsp");
    const configuredMisePath = config.get<string | undefined>("rubyVersionManager.miseExecutablePath");

    if (configuredMisePath) {
      return this.ensureMiseExistsAt(configuredMisePath);
    }

    // Possible mise installation directories. If none match, fall back to the PATH.
    //
    // 1. Installation from curl | sh (per mise.jdx.dev Getting Started)
    // 2. Homebrew M series
    // 3. Homebrew Intel / Linuxbrew
    // 4. Linuxbrew (legacy)
    // 5. Installation from `apt install mise`
    const possiblePaths = [
      vscode.Uri.joinPath(vscode.Uri.file(os.homedir()), ".local", "bin"),
      vscode.Uri.joinPath(vscode.Uri.file("/"), "opt", "homebrew", "bin"),
      vscode.Uri.joinPath(vscode.Uri.file("/"), "usr", "local", "bin"),
      vscode.Uri.joinPath(vscode.Uri.file("/"), "home", "linuxbrew", ".linuxbrew", "bin"),
      vscode.Uri.joinPath(vscode.Uri.file("/"), "usr", "bin"),
    ];
    return this.findExec(possiblePaths, "mise");
  }

  private async ensureMiseExistsAt(path: string): Promise<string> {
    try {
      await vscode.workspace.fs.stat(vscode.Uri.file(path));
      return path;
    } catch (_error: any) {
      throw new NonReportableError(`The Ruby LSP version manager is configured to be Mise, but ${path} does not exist`);
    }
  }
}
