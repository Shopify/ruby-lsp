import os from "os";

import * as vscode from "vscode";

import { VersionManager, ActivationResult } from "./versionManager";
import { WorkspaceChannel } from "../workspaceChannel";
import { pathToUri } from "../common";

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
      pathToUri(os.homedir(), ".local", "bin", "mise"),
      pathToUri("/", "opt", "homebrew", "bin", "mise"),
      pathToUri("/", "usr", "bin", "mise"),
    ];
  }

  static async detect(
    _workspaceFolder: vscode.WorkspaceFolder,
    _outputChannel: WorkspaceChannel,
  ): Promise<vscode.Uri | undefined> {
    return VersionManager.findFirst(Mise.getPossiblePaths());
  }

  async activate(): Promise<ActivationResult> {
    const miseUri = await this.findVersionManagerUri(
      "Mise",
      "rubyVersionManager.miseExecutablePath",
      Mise.getPossiblePaths(),
      () => Mise.detect(this.workspaceFolder, this.outputChannel),
    );

    // The exec command in Mise is called `x`
    const parsedResult = await this.runEnvActivationScript(`${miseUri.fsPath} x -- ruby`);

    return {
      env: { ...process.env, ...parsedResult.env },
      yjit: parsedResult.yjit,
      version: parsedResult.version,
      gemPath: parsedResult.gemPath,
    };
  }
}
