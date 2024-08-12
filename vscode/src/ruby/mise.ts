/* eslint-disable no-process-env */
import os from "os";

import * as vscode from "vscode";

import { VersionManager, ActivationResult } from "./versionManager";

// Mise (mise en place) is a manager for dev tools, environment variables and tasks
//
// Learn more: https://github.com/jdx/mise
export class Mise extends VersionManager {
  async activate(): Promise<ActivationResult> {
    const miseUri = await this.findMiseUri();

    const activationScript =
      "STDERR.print({ env: ENV.to_h, yjit: !!defined?(RubyVM::YJIT), version: RUBY_VERSION }.to_json)";

    // The exec command in Mise is called `x`
    const result = await this.runScript(
      `${miseUri.fsPath} x -- ruby -W0 -rjson -e '${activationScript}'`,
    );

    const parsedResult = this.parseWithErrorHandling(result.stderr);
    return {
      env: { ...process.env, ...parsedResult.env },
      yjit: parsedResult.yjit,
      version: parsedResult.version,
    };
  }

  async findMiseUri(): Promise<vscode.Uri> {
    const config = vscode.workspace.getConfiguration("rubyLsp");
    const misePath = config.get<string | undefined>(
      "rubyVersionManager.miseExecutablePath",
    );
    const miseUri = misePath
      ? vscode.Uri.file(misePath)
      : vscode.Uri.joinPath(
          vscode.Uri.file(os.homedir()),
          ".local",
          "bin",
          "mise",
        );

    try {
      await vscode.workspace.fs.stat(miseUri);
      return miseUri;
    } catch (error: any) {
      // Couldn't find it
    }

    throw new Error(
      `The Ruby LSP version manager is configured to be Mise, but ${miseUri.fsPath} does not exist`,
    );
  }
}
