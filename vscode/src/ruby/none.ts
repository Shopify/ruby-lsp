import * as vscode from "vscode";

import { WorkspaceChannel } from "../workspaceChannel";

import { VersionManager, ActivationResult } from "./versionManager";

// None
//
// This "version manager" represents the case where no manager is used, but the environment still needs to be inserted
// into the NodeJS process. For example, when you use Docker, install Ruby through Homebrew or use some other mechanism
// to have Ruby available in your PATH automatically.
//
// If you don't have Ruby automatically available in your PATH and are not using a version manager, look into
// configuring custom Ruby activation
export class None extends VersionManager {
  private readonly rubyPath: string;

  constructor(
    workspaceFolder: vscode.WorkspaceFolder,
    outputChannel: WorkspaceChannel,
    context: vscode.ExtensionContext,
    manuallySelectRuby: () => Promise<void>,
    rubyPath?: string,
  ) {
    super(workspaceFolder, outputChannel, context, manuallySelectRuby);
    this.rubyPath = rubyPath ?? "ruby";
  }

  async activate(): Promise<ActivationResult> {
    const parsedResult = await this.runEnvActivationScript(this.rubyPath);

    return {
      env: { ...process.env, ...parsedResult.env },
      yjit: parsedResult.yjit,
      version: parsedResult.version,
      gemPath: parsedResult.gemPath,
    };
  }
}
