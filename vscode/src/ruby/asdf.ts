import os from "os";
import path from "path";

import * as vscode from "vscode";

import { VersionManager, ActivationResult, DetectionResult } from "./versionManager";
import { WorkspaceChannel } from "../workspaceChannel";
import { pathToUri } from "../common";
import { ExecutableNotFoundError } from "./errors";

// A tool to manage multiple runtime versions with a single CLI tool
//
// Learn more: https://github.com/asdf-vm/asdf
export class Asdf extends VersionManager {
  private static getPossibleExecutablePaths(): vscode.Uri[] {
    // These directories are where we can find the ASDF executable for v0.16 and above
    return [pathToUri("/", "opt", "homebrew", "bin"), pathToUri("/", "usr", "local", "bin")];
  }

  private static getPossibleScriptPaths(): vscode.Uri[] {
    const scriptName = path.basename(vscode.env.shell) === "fish" ? "asdf.fish" : "asdf.sh";

    // Possible ASDF installation paths as described in https://asdf-vm.com/guide/getting-started.html#_3-install-asdf.
    // In order, the methods of installation are:
    // 1. Git
    // 2. Pacman
    // 3. Homebrew M series
    // 4. Homebrew Intel series
    return [
      pathToUri(os.homedir(), ".asdf", scriptName),
      pathToUri("/", "opt", "asdf-vm", scriptName),
      pathToUri("/", "opt", "homebrew", "opt", "asdf", "libexec", scriptName),
      pathToUri("/", "usr", "local", "opt", "asdf", "libexec", scriptName),
    ];
  }

  static async detect(
    workspaceFolder: vscode.WorkspaceFolder,
    outputChannel: WorkspaceChannel,
  ): Promise<DetectionResult> {
    // Check for v0.16+ executables first
    const executablePaths = Asdf.getPossibleExecutablePaths();
    const asdfExecPaths = executablePaths.map((dir) => vscode.Uri.joinPath(dir, "asdf"));
    const execResult = await VersionManager.findFirst(asdfExecPaths);
    if (execResult) {
      return { type: "path", uri: execResult };
    }

    // Check for < v0.16 scripts
    const scriptResult = await VersionManager.findFirst(Asdf.getPossibleScriptPaths());
    if (scriptResult) {
      return { type: "path", uri: scriptResult };
    }

    // check on PATH
    const toolExists = await VersionManager.toolExists("asdf", workspaceFolder, outputChannel);
    if (toolExists) {
      return { type: "semantic", marker: "asdf" };
    }

    return { type: "none" };
  }

  async activate(): Promise<ActivationResult> {
    // Prefer the path configured by the user, then use detect() to find ASDF
    const configuredPath = await this.getConfiguredAsdfPath();
    let asdfUri: vscode.Uri | undefined;

    if (configuredPath) {
      asdfUri = vscode.Uri.file(configuredPath);
    } else {
      const result = await Asdf.detect(this.workspaceFolder, this.outputChannel);

      if (result.type === "path") {
        asdfUri = result.uri;
      } else if (result.type === "semantic") {
        // Use ASDF from PATH
      } else {
        throw new ExecutableNotFoundError("asdf", [
          ...Asdf.getPossibleExecutablePaths().map((uri) => uri.fsPath),
          ...Asdf.getPossibleScriptPaths().map((uri) => uri.fsPath),
        ]);
      }
    }

    let baseCommand: string;

    if (asdfUri) {
      const asdfPath = asdfUri.fsPath;
      // If there's no extension name, then we are using the ASDF executable directly. If there is an extension, then it's
      // a shell script and we have to source it first
      baseCommand = path.extname(asdfPath) === "" ? asdfPath : `. ${asdfPath} && asdf`;
    } else {
      baseCommand = "asdf";
    }

    const parsedResult = await this.runEnvActivationScript(`${baseCommand} exec ruby`);

    return {
      env: { ...process.env, ...parsedResult.env },
      yjit: parsedResult.yjit,
      version: parsedResult.version,
      gemPath: parsedResult.gemPath,
    };
  }

  private async getConfiguredAsdfPath(): Promise<string | undefined> {
    const config = vscode.workspace.getConfiguration("rubyLsp");
    const asdfPath = config.get<string | undefined>("rubyVersionManager.asdfExecutablePath");

    if (!asdfPath) {
      return;
    }

    const configuredPath = vscode.Uri.file(asdfPath);

    try {
      await vscode.workspace.fs.stat(configuredPath);
      this.outputChannel.info(`Using configured ASDF executable path: ${asdfPath}`);
      return configuredPath.fsPath;
    } catch (_error: unknown) {
      throw new ExecutableNotFoundError("asdf", [configuredPath.fsPath], configuredPath.fsPath);
    }
  }
}
