/* eslint-disable no-process-env */

import path from "path";
import os from "os";

import * as vscode from "vscode";

import { asyncExec } from "../common";

import { VersionManager, ActivationResult } from "./versionManager";

// A tool to manage multiple runtime versions with a single CLI tool
//
// Learn more: https://github.com/asdf-vm/asdf
export class Asdf extends VersionManager {
  async activate(): Promise<ActivationResult> {
    const asdfUri = await this.findAsdfInstallation();
    const asdfDaraDirUri = await this.findAsdfDataDir();
    const activationScript =
      "STDERR.print({env: ENV.to_h,yjit:!!defined?(RubyVM::YJIT),version:RUBY_VERSION}.to_json)";

    const result = await asyncExec(
      `. ${asdfUri.fsPath} && asdf exec ruby -W0 -rjson -e '${activationScript}'`,
      {
        cwd: this.bundleUri.fsPath,
        env: {
          ASDF_DIR: path.dirname(asdfUri.fsPath),
          ASDF_DATA_DIR: asdfDaraDirUri.fsPath,
        },
      },
    );

    const parsedResult = this.parseWithErrorHandling(result.stderr);

    // ASDF does not set GEM_HOME or GEM_PATH. It also does not add the gem bin directories to the PATH. Instead, it
    // adds its shims directory to the PATH, where all gems have a shim that invokes the gem's executable with the right
    // version
    parsedResult.env.PATH = [
      vscode.Uri.joinPath(asdfDaraDirUri, "shims").fsPath,
      parsedResult.env.PATH,
    ].join(path.delimiter);

    return {
      env: { ...process.env, ...parsedResult.env },
      yjit: parsedResult.yjit,
      version: parsedResult.version,
    };
  }

  // Find the ASDF data directory. The default is for this to be in the same directories where we'd find the asdf.sh
  // file, but that may not be the case for a Homebrew installation, in which case the we'd have
  // `/opt/homebrew/opt/asdf/libexec/asdf.sh`, but the data directory might be `~/.asdf`
  async findAsdfDataDir(): Promise<vscode.Uri> {
    // In order, the data locations are:
    // 1. Default
    // 2. XDG Base Directory
    // 3. Homebrew M series
    // 4. Homebrew Intel series
    const possiblePaths = [
      vscode.Uri.joinPath(vscode.Uri.file(os.homedir()), ".asdf"),
      vscode.Uri.joinPath(
        vscode.Uri.file(os.homedir()),
        ".local",
        "share",
        "asdf",
      ),
      vscode.Uri.joinPath(vscode.Uri.file("/"), "opt", "asdf-vm"),
      vscode.Uri.joinPath(
        vscode.Uri.file("/"),
        "opt",
        "homebrew",
        "opt",
        "asdf",
        "libexec",
      ),
      vscode.Uri.joinPath(
        vscode.Uri.file("/"),
        "usr",
        "local",
        "opt",
        "asdf",
        "libexec",
      ),
    ];

    for (const possiblePath of possiblePaths) {
      try {
        await vscode.workspace.fs.stat(
          vscode.Uri.joinPath(possiblePath, "shims"),
        );
        return possiblePath;
      } catch (error: any) {
        // Continue looking
      }
    }

    throw new Error(
      `Could not find ASDF data dir. Searched in ${possiblePaths.join(", ")}`,
    );
  }

  // Only public for testing. Finds the ASDF installation URI based on what's advertised in the ASDF documentation
  async findAsdfInstallation(): Promise<vscode.Uri> {
    // Possible ASDF installation paths as described in https://asdf-vm.com/guide/getting-started.html#_3-install-asdf.
    // In order, the methods of installation are:
    // 1. Git
    // 2. Pacman
    // 3. Homebrew M series
    // 4. Homebrew Intel series
    const possiblePaths = [
      vscode.Uri.joinPath(vscode.Uri.file(os.homedir()), ".asdf", "asdf.sh"),
      vscode.Uri.joinPath(vscode.Uri.file("/"), "opt", "asdf-vm", "asdf.sh"),
      vscode.Uri.joinPath(
        vscode.Uri.file("/"),
        "opt",
        "homebrew",
        "opt",
        "asdf",
        "libexec",
        "asdf.sh",
      ),
      vscode.Uri.joinPath(
        vscode.Uri.file("/"),
        "usr",
        "local",
        "opt",
        "asdf",
        "libexec",
        "asdf.sh",
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
