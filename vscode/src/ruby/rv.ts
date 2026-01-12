import * as vscode from "vscode";

import { VersionManager, ActivationResult } from "./versionManager";
import { pathToUri } from "../common";
import { WorkspaceChannel } from "../workspaceChannel";

// Manage your Ruby environment with rv
//
// Learn more: https://github.com/spinel-coop/rv
export class Rv extends VersionManager {
  private static getPossiblePaths(): vscode.Uri[] {
    return [
      pathToUri("/", "home", "linuxbrew", ".linuxbrew", "bin", "rv"),
      pathToUri("/", "usr", "local", "bin", "rv"),
      pathToUri("/", "opt", "homebrew", "bin", "rv"),
      pathToUri("/", "usr", "bin", "rv"),
    ];
  }

  static async detect(
    _workspaceFolder: vscode.WorkspaceFolder,
    _outputChannel: WorkspaceChannel,
  ): Promise<vscode.Uri | undefined> {
    return VersionManager.findFirst(Rv.getPossiblePaths());
  }

  async activate(): Promise<ActivationResult> {
    const rvExec = await this.findVersionManagerUri(
      "Rv",
      "rubyVersionManager.rvExecutablePath",
      Rv.getPossiblePaths(),
      () => Rv.detect(this.workspaceFolder, this.outputChannel),
    );
    const parsedResult = await this.runEnvActivationScript(`${rvExec.fsPath} ruby run --`);

    return {
      env: { ...process.env, ...parsedResult.env },
      yjit: parsedResult.yjit,
      version: parsedResult.version,
      gemPath: parsedResult.gemPath,
    };
  }
}
