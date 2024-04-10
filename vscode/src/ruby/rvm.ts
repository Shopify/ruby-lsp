/* eslint-disable no-process-env */
import os from "os";

import * as vscode from "vscode";

import { asyncExec } from "../common";

import { ActivationResult, VersionManager } from "./versionManager";

// Ruby enVironment Manager. It manages Ruby application environments and enables switching between them.
// Learn more:
// - https://github.com/rvm/rvm
// - https://rvm.io
export class Rvm extends VersionManager {
  async activate(): Promise<ActivationResult> {
    const activationScript =
      "STDERR.print({ env: ENV.to_h, yjit: !!defined?(RubyVM::YJIT), version: RUBY_VERSION }.to_json)";

    const installationPath = await this.findRvmInstallation();

    const result = await asyncExec(
      `${installationPath.fsPath} -W0 -rjson -e '${activationScript}'`,
      {
        cwd: this.bundleUri.fsPath,
      },
    );

    const parsedResult = JSON.parse(result.stderr);
    const activatedKeys = Object.entries(parsedResult.env)
      .map(([key, value]) => `${key}=${value}`)
      .join(" ");

    this.outputChannel.info(`Activated Ruby environment: ${activatedKeys}`);

    return {
      env: { ...process.env, ...parsedResult.env },
      yjit: parsedResult.yjit,
      version: parsedResult.version,
    };
  }

  async findRvmInstallation(): Promise<vscode.Uri> {
    const possiblePaths = [
      vscode.Uri.joinPath(
        vscode.Uri.file(os.homedir()),
        ".rvm",
        "bin",
        "rvm-auto-ruby",
      ),
      vscode.Uri.joinPath(
        vscode.Uri.file("/"),
        "usr",
        "local",
        "rvm",
        "bin",
        "rvm-auto-ruby",
      ),
      vscode.Uri.joinPath(
        vscode.Uri.file("/"),
        "usr",
        "share",
        "rvm",
        "bin",
        "rvm-auto-ruby",
      ),
    ];

    for (const uri of possiblePaths) {
      try {
        await vscode.workspace.fs.stat(uri);
        return uri;
      } catch (_error: any) {
        // Continue to the next installation path
      }
    }

    throw new Error(
      `Cannot find RVM installation directory. Searched in ${possiblePaths.map((uri) => uri.fsPath).join(",")}`,
    );
  }
}
