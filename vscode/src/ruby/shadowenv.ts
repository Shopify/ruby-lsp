import * as vscode from "vscode";

import { asyncExec } from "../common";

import { VersionManager, ActivationResult } from "./versionManager";

// Shadowenv is a tool that allows managing environment variables upon entering a directory. It allows users to manage
// which Ruby version should be used for each project, in addition to other customizations such as GEM_HOME.
//
// Learn more: https://github.com/Shopify/shadowenv
export class UntrustedWorkspaceError extends Error {}

export class Shadowenv extends VersionManager {
  async activate(): Promise<ActivationResult> {
    try {
      await vscode.workspace.fs.stat(vscode.Uri.joinPath(this.bundleUri, ".shadowenv.d"));
    } catch (_error: any) {
      throw new Error(
        "The Ruby LSP version manager is configured to be shadowenv, \
        but no .shadowenv.d directory was found in the workspace",
      );
    }

    const shadowenvExec = await this.findExec([], "shadowenv");

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
    } catch (error: any) {
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

        throw new UntrustedWorkspaceError("Cannot activate Ruby environment in an untrusted workspace");
      }

      try {
        await asyncExec("shadowenv --version");
      } catch (_error: any) {
        throw new Error(
          `Shadowenv executable not found. Ensure it is installed and available in the PATH.
           This error may happen if your shell configuration is failing to be sourced from the editor or if
           another extension is mutating the process PATH.`,
        );
      }

      // If it failed for some other reason, present the error to the user
      throw new Error(`Failed to activate Ruby environment with Shadowenv: ${error.message}`);
    }
  }
}
