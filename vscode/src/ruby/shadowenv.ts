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
      vscode.workspace.fs.stat(
        vscode.Uri.joinPath(this.bundleUri, ".shadowenv.d"),
      );
    } catch (error: any) {
      throw new Error(
        "The Ruby LSP version manager is configured to be shadowenv, \
        but no .shadowenv.d directory was found in the workspace",
      );
    }

    const activationScript =
      "STDERR.print({ env: ENV.to_h, yjit: !!defined?(RubyVM::YJIT), version: RUBY_VERSION }.to_json)";

    try {
      const result = await asyncExec(
        `shadowenv exec -- ruby -W0 -rjson -e '${activationScript}'`,
        {
          cwd: this.bundleUri.fsPath,
        },
      );

      const parsedResult = JSON.parse(result.stderr);
      return {
        env: { ...process.env, ...parsedResult.env },
        yjit: parsedResult.yjit,
        version: parsedResult.version,
      };
    } catch (error: any) {
      // If running `shadowev exec` fails, it's typically because the workspace has not been trusted yet. Here we offer
      // to trust it and fail it the user decides to not the trust the workspace (since in that case, we are unable to
      // activate the Ruby environment).
      const answer = await vscode.window.showErrorMessage(
        `Failed to run shadowenv exec. Is ${this.bundleUri.fsPath} trusted? Run 'shadowenv trust --help' to know more`,
        "Trust workspace",
        "Cancel",
      );

      if (answer === "Trust workspace") {
        await asyncExec("shadowenv trust", { cwd: this.bundleUri.fsPath });
        return this.activate();
      }

      throw new Error(
        "Cannot activate Ruby environment in an untrusted workspace",
      );
    }
  }
}
