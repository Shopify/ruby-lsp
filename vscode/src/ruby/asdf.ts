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
    // These directories are where we can find the ASDF executable for v0.16 and above
    const possibleExecutablePaths = [
      vscode.Uri.joinPath(vscode.Uri.file("/"), "opt", "homebrew", "bin"),
      vscode.Uri.joinPath(vscode.Uri.file("/"), "usr", "local", "bin"),
    ];

    // Prefer the path configured by the user, then the ASDF scripts for versions below v0.16 and finally the
    // executables for v0.16 and above
    const asdfPath =
      (await this.getConfiguredAsdfPath()) ??
      (await this.findAsdfInstallation()) ??
      (await this.findExec(possibleExecutablePaths, "asdf"));

    // If there's no extension name, then we are using the ASDF executable directly. If there is an extension, then it's
    // a shell script and we have to source it first
    const baseCommand =
      path.extname(asdfPath) === "" ? asdfPath : `. ${asdfPath} && asdf`;

    const parsedResult = await this.runEnvActivationScript(
      `${baseCommand} exec ruby`,
    );

    return {
      env: { ...process.env, ...parsedResult.env },
      yjit: parsedResult.yjit,
      version: parsedResult.version,
      gemPath: parsedResult.gemPath,
    };
  }

  // Only public for testing. Finds the ASDF installation URI based on what's advertised in the ASDF documentation
  async findAsdfInstallation(): Promise<string | undefined> {
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
        return possiblePath.fsPath;
      } catch (error: any) {
        // Continue looking
      }
    }

    this.outputChannel.info(
      `Could not find installation for ASDF < v0.16. Searched in ${possiblePaths.join(", ")}`,
    );
    return undefined;
  }

  private async getConfiguredAsdfPath(): Promise<string | undefined> {
    const config = vscode.workspace.getConfiguration("rubyLsp");
    const asdfPath = config.get<string | undefined>(
      "rubyVersionManager.asdfExecutablePath",
    );

    if (!asdfPath) {
      return;
    }

    const configuredPath = vscode.Uri.file(asdfPath);

    try {
      await vscode.workspace.fs.stat(configuredPath);
      this.outputChannel.info(
        `Using configured ASDF executable path: ${asdfPath}`,
      );
      return configuredPath.fsPath;
    } catch (error: any) {
      throw new Error(
        `ASDF executable configured as ${configuredPath}, but that file doesn't exist`,
      );
    }
  }
}
