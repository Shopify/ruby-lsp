/* eslint-disable no-process-env */

import os from "os";
import path from "path";

import * as vscode from "vscode";

import { VersionManager, ActivationResult } from "./versionManager";

// A tool to manage multiple runtime versions with a single CLI tool
//
// Learn more: https://github.com/asdf-vm/asdf
export class Asdf extends VersionManager {
  async activate(): Promise<ActivationResult> {
    const asdfUri = await this.findAsdfInstallation();
    const activationScript =
      "STDERR.print({env: ENV.to_h,yjit:!!defined?(RubyVM::YJIT),version:RUBY_VERSION}.to_json)";

    const result = await this.runScript(
      `. ${asdfUri.fsPath} && asdf exec ruby -W0 -rjson -e '${activationScript}'`,
    );

    const parsedResult = this.parseWithErrorHandling(result.stderr);

    return {
      env: { ...process.env, ...parsedResult.env },
      yjit: parsedResult.yjit,
      version: parsedResult.version,
    };
  }

  // Only public for testing. Finds the ASDF installation URI based on what's advertised in the ASDF documentation
  async findAsdfInstallation(): Promise<vscode.Uri> {
    const scriptName =
      path.basename(vscode.env.shell) === "fish" ? "asdf.fish" : "asdf.sh";

    // Possible ASDF installation paths as described in https://asdf-vm.com/guide/getting-started.html#_3-install-asdf.
    // In order, the methods of installation are:
    // 1. Git
    // 2. Pacman
    // 3. Homebrew M series
    // 4. Homebrew Intel series
    const possiblePaths = [
      vscode.Uri.joinPath(vscode.Uri.file(os.homedir()), ".asdf", scriptName),
      vscode.Uri.joinPath(vscode.Uri.file("/"), "opt", "asdf-vm", scriptName),
      vscode.Uri.joinPath(
        vscode.Uri.file("/"),
        "opt",
        "homebrew",
        "opt",
        "asdf",
        "libexec",
        scriptName,
      ),
      vscode.Uri.joinPath(
        vscode.Uri.file("/"),
        "usr",
        "local",
        "opt",
        "asdf",
        "libexec",
        scriptName,
      ),
    ];

    for (const possiblePath of possiblePaths) {
      try {
        await vscode.workspace.fs.stat(possiblePath);
        return possiblePath;
      } catch (error: any) {
        // Continue looking
      }
    }

    throw new Error(
      `Could not find ASDF installation. Searched in ${possiblePaths.join(", ")}`,
    );
  }
}
