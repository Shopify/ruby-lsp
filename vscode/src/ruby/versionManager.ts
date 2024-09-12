/* eslint-disable no-process-env */
import path from "path";

import * as vscode from "vscode";

import { WorkspaceChannel } from "../workspaceChannel";
import { asyncExec } from "../common";
import { getCustomBundleGemfile } from "../bundleGemfileHelper";

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
    this.customBundleGemfile = getCustomBundleGemfile(this.workspaceFolder);

    this.bundleUri = this.customBundleGemfile
      ? vscode.Uri.file(path.dirname(this.customBundleGemfile))
      : workspaceFolder.uri;
  }

  // Activate the Ruby environment for the version manager, returning all of the necessary information to boot the
  // language server
  abstract activate(): Promise<ActivationResult>;

  protected parseWithErrorHandling(json: string) {
    try {
      return JSON.parse(json);
    } catch (error: any) {
      this.outputChannel.error(
        `Tried parsing invalid JSON environment: ${json}`,
      );

      throw error;
    }
  }

  // Runs the given command in the directory for the Bundle, using the user's preferred shell and inheriting the current
  // process environment
  protected runScript(command: string) {
    const shell = vscode.env.shell.length > 0 ? vscode.env.shell : undefined;

    this.outputChannel.info(
      `Running command: \`${command}\` in ${this.bundleUri.fsPath} using shell: ${shell}`,
    );
    this.outputChannel.debug(
      `Environment used for command: ${JSON.stringify(process.env)}`,
    );

    return asyncExec(command, {
      cwd: this.bundleUri.fsPath,
      shell,
      env: process.env,
    });
  }
}
