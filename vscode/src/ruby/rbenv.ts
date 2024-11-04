/* eslint-disable no-process-env */
import * as vscode from "vscode";

import { VersionManager, ActivationResult } from "./versionManager";

// Seamlessly manage your app’s Ruby environment with rbenv.
//
// Learn more: https://github.com/rbenv/rbenv
export class Rbenv extends VersionManager {
  async activate(): Promise<ActivationResult> {
    const rbenvExec = await this.findExec(
      [vscode.Uri.file("/opt/homebrew/bin"), vscode.Uri.file("/usr/local/bin")],
      "rbenv",
    );

    const parsedResult = await this.runEnvActivationScript(
      `${rbenvExec} exec ruby`,
    );

    return {
      env: { ...process.env, ...parsedResult.env },
      yjit: parsedResult.yjit,
      version: parsedResult.version,
      gemPath: parsedResult.gemPath,
    };
  }
}
