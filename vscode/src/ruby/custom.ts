import * as vscode from "vscode";

import { VersionManager, ActivationResult, DetectionResult } from "./versionManager";
import { MissingConfigurationError } from "./errors";

// Custom
//
// Custom Ruby environment activation can be used for all cases where an existing version manager does not suffice.
// Users are allowed to define a shell script that runs before calling ruby, giving them the chance to modify the PATH,
// GEM_HOME and GEM_PATH as needed to find the correct Ruby runtime.
export class Custom extends VersionManager {
  // eslint-disable-next-line @typescript-eslint/require-await
  static async detect(
    _workspaceFolder: vscode.WorkspaceFolder,
    _outputChannel: vscode.LogOutputChannel,
  ): Promise<DetectionResult> {
    return { type: "none" };
  }

  async activate(): Promise<ActivationResult> {
    const parsedResult = await this.runEnvActivationScript(`${this.customCommand()} && ruby`);

    return {
      env: { ...process.env, ...parsedResult.env },
      yjit: parsedResult.yjit,
      version: parsedResult.version,
      gemPath: parsedResult.gemPath,
    };
  }

  customCommand() {
    const configuration = vscode.workspace.getConfiguration("rubyLsp");
    const customCommand: string | undefined = configuration.get("customRubyCommand");

    if (customCommand === undefined) {
      throw new MissingConfigurationError("custom", "rubyLsp.customRubyCommand");
    }

    return customCommand;
  }
}
