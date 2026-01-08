import * as vscode from "vscode";

import { asyncExec } from "../common";
import {
  VersionManagerDirectoryNotFoundError,
  UntrustedWorkspaceError,
  ExecutableNotFoundError,
  ActivationError,
} from "./errors";

import { VersionManager, ActivationResult, DetectionResult } from "./versionManager";

// Shadowenv is a tool that allows managing environment variables upon entering a directory. It allows users to manage
// which Ruby version should be used for each project, in addition to other customizations such as GEM_HOME.
//
// Learn more: https://github.com/Shopify/shadowenv

export class Shadowenv extends VersionManager {
  private static async shadowenvDirExists(workspaceUri: vscode.Uri): Promise<boolean> {
    return VersionManager.pathExists(vscode.Uri.joinPath(workspaceUri, ".shadowenv.d"));
  }

  static async detect(
    workspaceFolder: vscode.WorkspaceFolder,
    _outputChannel: vscode.LogOutputChannel,
  ): Promise<DetectionResult> {
    const exists = await Shadowenv.shadowenvDirExists(workspaceFolder.uri);
    if (exists) {
      return { type: "path", uri: vscode.Uri.joinPath(workspaceFolder.uri, ".shadowenv.d") };
    }
    return { type: "none" };
  }

  async activate(): Promise<ActivationResult> {
    const exists = await Shadowenv.shadowenvDirExists(this.bundleUri);
    if (!exists) {
      throw new VersionManagerDirectoryNotFoundError("shadowenv", ".shadowenv.d");
    }

    const shadowenvExec = await this.findExec([vscode.Uri.file("/opt/homebrew/bin")], "shadowenv");

    try {
      const parsedResult = await this.runEnvActivationScript(`${shadowenvExec} exec -- ruby`);

      // Do not let Shadowenv change the BUNDLE_GEMFILE. The server has to be able to control this in order to properly
      // set up the environment
      delete parsedResult.env.BUNDLE_GEMFILE;

      return {
        env: { ...process.env, ...parsedResult.env },
        yjit: parsedResult.yjit,
        version: parsedResult.version,
        gemPath: parsedResult.gemPath,
      };
    } catch (error: unknown) {
      const err = error as Error;
      // If the workspace is untrusted, offer to trust it for the user
      if (err.message.includes("untrusted shadowenv program")) {
        const answer = await vscode.window.showErrorMessage(
          `Tried to activate Shadowenv, but the workspace is untrusted.
           Workspaces must be trusted to before allowing Shadowenv to load the environment for security reasons.`,
          "Trust workspace",
          "Shutdown Ruby LSP",
        );

        if (answer === "Trust workspace") {
          await asyncExec("shadowenv trust", { cwd: this.bundleUri.fsPath });
          return this.activate();
        }

        throw new UntrustedWorkspaceError("shadowenv");
      }

      try {
        await asyncExec("shadowenv --version");
      } catch (_error: unknown) {
        throw new ExecutableNotFoundError("shadowenv", ["PATH"]);
      }

      // If it failed for some other reason, present the error to the user
      throw new ActivationError(`Failed to activate Ruby environment with Shadowenv: ${err.message}`, "shadowenv", err);
    }
  }
}
