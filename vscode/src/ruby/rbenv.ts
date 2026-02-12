import * as vscode from "vscode";

import { VersionManager, ActivationResult, DetectionResult } from "./versionManager";
import { WorkspaceChannel } from "../workspaceChannel";

// Seamlessly manage your app’s Ruby environment with rbenv.
//
// Learn more: https://github.com/rbenv/rbenv
export class Rbenv extends VersionManager {
  static async detect(
    workspaceFolder: vscode.WorkspaceFolder,
    outputChannel: WorkspaceChannel,
  ): Promise<DetectionResult> {
    const exists = await VersionManager.toolExists("rbenv", workspaceFolder, outputChannel);
    return exists ? { type: "semantic", marker: "rbenv" } : { type: "none" };
  }

  async activate(): Promise<ActivationResult> {
    const rbenvExec = await this.findRbenv();

    const parsedResult = await this.runEnvActivationScript(`${rbenvExec} exec ruby`);

    return {
      env: { ...process.env, ...parsedResult.env },
      yjit: parsedResult.yjit,
      version: parsedResult.version,
      gemPath: parsedResult.gemPath,
    };
  }

  private async findRbenv(): Promise<string> {
    const config = vscode.workspace.getConfiguration("rubyLsp");
    const configuredRbenvPath = config.get<string | undefined>("rubyVersionManager.rbenvExecutablePath");

    if (configuredRbenvPath) {
      return this.ensureRbenvExistsAt(configuredRbenvPath);
    } else {
      return this.findExec([vscode.Uri.file("/opt/homebrew/bin"), vscode.Uri.file("/usr/local/bin")], "rbenv");
    }
  }

  private async ensureRbenvExistsAt(path: string): Promise<string> {
    try {
      await vscode.workspace.fs.stat(vscode.Uri.file(path));

      return path;
    } catch (_error: any) {
      throw new Error(`The Ruby LSP version manager is configured to be rbenv, but ${path} does not exist`);
    }
  }
}
