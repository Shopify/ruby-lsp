/* eslint-disable no-process-env */
import * as vscode from "vscode";

import { asyncExec } from "../common";

import { VersionManager, ActivationResult } from "./versionManager";

// Custom
//
// Custom Ruby environment activation can be used for all cases where an existing version manager does not suffice.
// Users are allowed to define a shell script that runs before calling ruby, giving them the chance to modify the PATH,
// GEM_HOME and GEM_PATH as needed to find the correct Ruby runtime.
export class Custom extends VersionManager {
  async activate(): Promise<ActivationResult> {
    const activationScript =
      "STDERR.print({ env: ENV.to_h, yjit: !!defined?(RubyVM::YJIT), version: RUBY_VERSION }.to_json)";

    const result = await asyncExec(
      `${this.customCommand()} && ruby -W0 -rjson -e '${activationScript}'`,
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
  }

  customCommand() {
    const configuration = vscode.workspace.getConfiguration("rubyLsp");
    const customCommand: string | undefined =
      configuration.get("customRubyCommand");

    if (customCommand === undefined) {
      throw new Error(
        "The customRubyCommand configuration must be set when 'custom' is selected as the version manager. \
        See the [README](https://github.com/Shopify/ruby-lsp/blob/main/vscode/VERSION_MANAGERS.md) for instructions.",
      );
    }

    return customCommand;
  }
}
