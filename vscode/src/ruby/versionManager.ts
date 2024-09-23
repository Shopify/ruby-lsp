/* eslint-disable no-process-env */
import path from "path";
import os from "os";

import * as vscode from "vscode";

import { WorkspaceChannel } from "../workspaceChannel";
import { asyncExec } from "../common";

export interface ActivationResult {
  env: NodeJS.ProcessEnv;
  yjit: boolean;
  version: string;
}

export const ACTIVATION_SEPARATOR = "RUBY_LSP_ACTIVATION_SEPARATOR";

export abstract class VersionManager {
  public activationScript = [
    `STDERR.print("${ACTIVATION_SEPARATOR}" + `,
    "{ env: ENV.to_h, yjit: !!defined?(RubyVM:: YJIT), version: RUBY_VERSION }.to_json + ",
    `"${ACTIVATION_SEPARATOR}")`,
  ].join("");

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

  protected async runEnvActivationScript(activatedRuby: string) {
    const result = await this.runScript(
      `${activatedRuby} -W0 -rjson -e '${this.activationScript}'`,
    );

    const activationContent = new RegExp(
      `${ACTIVATION_SEPARATOR}(.*)${ACTIVATION_SEPARATOR}`,
    ).exec(result.stderr);

    return this.parseWithErrorHandling(activationContent![1]);
  }

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
    let shell: string | undefined;

    // If the user has configured a default shell, we use that one since they are probably sourcing their version
    // manager scripts in that shell's configuration files. On Windows, we never set the shell no matter what to ensure
    // that activation runs on `cmd.exe` and not PowerShell, which avoids complex quoting and escaping issues.
    if (vscode.env.shell.length > 0 && os.platform() !== "win32") {
      shell = vscode.env.shell;
    }

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
