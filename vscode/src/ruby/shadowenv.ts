/* eslint-disable no-process-env */
import * as vscode from "vscode";

import { asyncExec } from "../common";

import { VersionManager, ActivationResult } from "./versionManager";

// Shadowenv is a tool that allows managing environment variables upon entering a directory. It allows users to manage
// which Ruby version should be used for each project, in addition to other customizations such as GEM_HOME.
//
// Learn more: https://github.com/Shopify/shadowenv
export class Shadowenv extends VersionManager {
  async activate(): Promise<ActivationResult> {
    try {
      await vscode.workspace.fs.stat(
        vscode.Uri.joinPath(this.bundleUri, ".shadowenv.d"),
      );
    } catch (error: any) {
      throw new Error(
        "The Ruby LSP version manager is configured to be shadowenv, \
        but no .shadowenv.d directory was found in the workspace",
      );
    }

    try {
      const parsedResult = await this.runEnvActivationScript(
        "shadowenv exec -- ruby",
      );

      return {
        env: { ...process.env, ...parsedResult.env },
        yjit: parsedResult.yjit,
        version: parsedResult.version,
      };
    } catch (error: any) {
      const { stdout } = await this.runScript("command -v shadowenv");

      if (stdout.trim().length === 0) {
        const answer = await vscode.window.showErrorMessage(
          `Couldn't find shadowenv executable. Double-check that it's installed and that it's in your PATH.`,
          "Reload window",
          "Cancel",
        );

        if (answer === "Reload window") {
          return vscode.commands.executeCommand(
            "workbench.action.reloadWindow",
          );
        }
      } else {
        // If running `shadowev exec` fails, it's typically because the workspace has not been trusted yet. Here we
        // offer to trust it and fail it the user decides to not the trust the workspace (since in that case, we are
        // unable to activate the Ruby environment).
        const answer = await vscode.window.showErrorMessage(
          `Failed to run shadowenv. Is ${this.bundleUri.fsPath} trusted? Run 'shadowenv trust --help' to know more`,
          "Trust workspace",
          "Cancel",
        );

        if (answer === "Trust workspace") {
          await asyncExec("shadowenv trust", { cwd: this.bundleUri.fsPath });
          return this.activate();
        }
      }

      throw new Error(
        "Cannot activate Ruby environment in an untrusted workspace",
      );
    }
  }
}
