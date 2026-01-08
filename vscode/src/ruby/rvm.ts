import os from "os";

import * as vscode from "vscode";

import { ActivationResult, VersionManager, DetectionResult } from "./versionManager";
import { WorkspaceChannel } from "../workspaceChannel";
import { pathToUri } from "../common";
import { ExecutableNotFoundError } from "./errors";

// Ruby enVironment Manager. It manages Ruby application environments and enables switching between them.
// Learn more:
// - https://github.com/rvm/rvm
// - https://rvm.io
export class Rvm extends VersionManager {
  static async detect(
    workspaceFolder: vscode.WorkspaceFolder,
    outputChannel: WorkspaceChannel,
  ): Promise<DetectionResult> {
    const exists = await VersionManager.toolExists("rvm", workspaceFolder, outputChannel);
    return exists ? { type: "semantic", marker: "rvm" } : { type: "none" };
  }

  async activate(): Promise<ActivationResult> {
    const installationPath = await this.findRvmInstallation();
    const parsedResult = await this.runEnvActivationScript(installationPath.fsPath);

    const activatedKeys = Object.entries(parsedResult.env)
      .map(([key, value]) => `${key}=${value}`)
      .join(" ");

    this.outputChannel.info(`Activated Ruby environment: ${activatedKeys}`);

    return {
      env: { ...process.env, ...parsedResult.env },
      yjit: parsedResult.yjit,
      version: parsedResult.version,
      gemPath: parsedResult.gemPath,
    };
  }

  async findRvmInstallation(): Promise<vscode.Uri> {
    const possiblePaths = [
      pathToUri(os.homedir(), ".rvm", "bin", "rvm-auto-ruby"),
      pathToUri("/", "usr", "local", "rvm", "bin", "rvm-auto-ruby"),
      pathToUri("/", "usr", "share", "rvm", "bin", "rvm-auto-ruby"),
    ];

    for (const uri of possiblePaths) {
      try {
        await vscode.workspace.fs.stat(uri);
        return uri;
      } catch (_error: any) {
        // Continue to the next installation path
      }
    }

    throw new ExecutableNotFoundError(
      "rvm",
      possiblePaths.map((uri) => uri.fsPath),
    );
  }
}
