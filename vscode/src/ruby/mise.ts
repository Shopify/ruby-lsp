import os from "os";

import * as vscode from "vscode";

import { VersionManager, ActivationResult } from "./versionManager";
import { WorkspaceChannel } from "../workspaceChannel";
import { pathToUri } from "../common";

// Mise (mise en place) is a manager for dev tools, environment variables and tasks
//
// Learn more: https://github.com/jdx/mise
export class Mise extends VersionManager {
  static async detect(
    _workspaceFolder: vscode.WorkspaceFolder,
    _outputChannel: WorkspaceChannel,
  ): Promise<vscode.Uri | undefined> {
    return this.findFirst(this.getPossiblePaths());
  }

  async activate(): Promise<ActivationResult> {
    const execUri = await this.findVersionManagerUri();

    const parsedResult = await this.runEnvActivationScript(this.getExecutionCommand(execUri.fsPath));

    return {
      env: { ...process.env, ...parsedResult.env },
      yjit: parsedResult.yjit,
      version: parsedResult.version,
      gemPath: parsedResult.gemPath,
    };
  }

  // Possible mise installation paths
  //
  // 1. Installation from curl | sh (per mise.jdx.dev Getting Started)
  // 2. Homebrew M series
  // 3. Installation from `apt install mise`
  protected static getPossiblePaths(): vscode.Uri[] {
    return [
      pathToUri(os.homedir(), ".local", "bin", "mise"),
      pathToUri("/", "opt", "homebrew", "bin", "mise"),
      pathToUri("/", "usr", "bin", "mise"),
    ];
  }

  protected getVersionManagerName(): string {
    return "Mise";
  }

  protected getConfigKey(): string {
    return "rubyVersionManager.miseExecutablePath";
  }

  protected getExecutionCommand(executablePath: string): string {
    // The exec command in Mise is called `x`
    return `${executablePath} x -- ruby`;
  }

  private async findVersionManagerUri(): Promise<vscode.Uri> {
    const constructor = this.constructor as typeof Mise;
    const managerName = this.getVersionManagerName();
    const configKey = this.getConfigKey();

    const config = vscode.workspace.getConfiguration("rubyLsp");
    const configuredPath = config.get<string | undefined>(configKey);

    if (configuredPath) {
      const uri = vscode.Uri.file(configuredPath);

      try {
        await vscode.workspace.fs.stat(uri);
        return uri;
      } catch (_error: any) {
        throw new Error(`${managerName} executable configured as ${uri.fsPath}, but that file doesn't exist`);
      }
    }

    const detectedPath = await constructor.detect(this.workspaceFolder, this.outputChannel);

    if (detectedPath) {
      return detectedPath;
    }

    const possiblePaths = constructor.getPossiblePaths();
    throw new Error(
      `The Ruby LSP version manager is configured to be ${managerName}, but could not find ${managerName} installation. Searched in
        ${possiblePaths.map((p) => p.fsPath).join(", ")}`,
    );
  }
}
