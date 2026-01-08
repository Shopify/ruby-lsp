import os from "os";

import * as vscode from "vscode";

import { VersionManager, ActivationResult } from "./versionManager";

// Mise (mise en place) is a manager for dev tools, environment variables and tasks
//
// Learn more: https://github.com/jdx/mise
export class Mise extends VersionManager {
  // Possible mise installation paths
  //
  // 1. Installation from curl | sh (per mise.jdx.dev Getting Started)
  // 2. Homebrew M series
  // 3. Installation from `apt install mise`
  private static getPossiblePaths(): vscode.Uri[] {
    return [
      vscode.Uri.joinPath(vscode.Uri.file(os.homedir()), ".local", "bin", "mise"),
      vscode.Uri.joinPath(vscode.Uri.file("/"), "opt", "homebrew", "bin", "mise"),
      vscode.Uri.joinPath(vscode.Uri.file("/"), "usr", "bin", "mise"),
    ];
  }

  static async detect(): Promise<vscode.Uri | undefined> {
    return VersionManager.findFirst(Mise.getPossiblePaths());
  }

  async activate(): Promise<ActivationResult> {
    const miseUri = await this.findMiseUri();

    // The exec command in Mise is called `x`
    const parsedResult = await this.runEnvActivationScript(`${miseUri.fsPath} x -- ruby`);

    return {
      env: { ...process.env, ...parsedResult.env },
      yjit: parsedResult.yjit,
      version: parsedResult.version,
      gemPath: parsedResult.gemPath,
    };
  }

  async findMiseUri(): Promise<vscode.Uri> {
    const config = vscode.workspace.getConfiguration("rubyLsp");
    const misePath = config.get<string | undefined>("rubyVersionManager.miseExecutablePath");

    if (misePath) {
      const configuredPath = vscode.Uri.file(misePath);

      try {
        await vscode.workspace.fs.stat(configuredPath);
        return configuredPath;
      } catch (_error: any) {
        throw new Error(`Mise executable configured as ${configuredPath.fsPath}, but that file doesn't exist`);
      }
    }

    const detectedPath = await Mise.detect();

    if (detectedPath) {
      return detectedPath;
    }

    const possiblePaths = Mise.getPossiblePaths();
    throw new Error(
      `The Ruby LSP version manager is configured to be Mise, but could not find Mise installation. Searched in
        ${possiblePaths.join(", ")}`,
    );
  }
}
