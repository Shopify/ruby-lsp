import path from "path";

import * as vscode from "vscode";

import { WorkspaceChannel } from "../workspaceChannel";

export interface ActivationResult {
  env: NodeJS.ProcessEnv;
  yjit: boolean;
  version: string;
}

export abstract class VersionManager {
  protected readonly outputChannel: WorkspaceChannel;
  protected readonly workspaceFolder: vscode.WorkspaceFolder;
  protected readonly bundleUri: vscode.Uri;
  private readonly customBundleGemfile?: string;

  constructor(
    workspaceFolder: vscode.WorkspaceFolder,
    outputChannel: WorkspaceChannel,
  ) {
    this.workspaceFolder = workspaceFolder;
    this.outputChannel = outputChannel;
    const customBundleGemfile: string = vscode.workspace
      .getConfiguration("rubyLsp")
      .get("bundleGemfile")!;

    if (customBundleGemfile.length > 0) {
      this.customBundleGemfile = path.isAbsolute(customBundleGemfile)
        ? customBundleGemfile
        : path.resolve(
            path.join(this.workspaceFolder.uri.fsPath, customBundleGemfile),
          );
    }

    this.bundleUri = this.customBundleGemfile
      ? vscode.Uri.file(path.dirname(this.customBundleGemfile))
      : workspaceFolder.uri;
  }

  // Activate the Ruby environment for the version manager, returning all of the necessary information to boot the
  // language server
  abstract activate(): Promise<ActivationResult>;
}
