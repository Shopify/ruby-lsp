import * as vscode from "vscode";

import { VersionManager, ActivationResult } from "./versionManager";

export class NixDevelop extends VersionManager {
  async activate(): Promise<ActivationResult> {
    const customCommand = this.customCommand();
    const command = `nix develop ${customCommand} --command ruby`;
    const parsedResult = await this.runEnvActivationScript(command);

    return {
      env: { ...process.env, ...parsedResult.env },
      yjit: parsedResult.yjit,
      version: parsedResult.version,
      gemPath: parsedResult.gemPath,
    };
  }

  private customCommand() {
    const configuration = vscode.workspace.getConfiguration("rubyLsp");
    const customCommand: string | undefined =
      configuration.get("customRubyCommand");

    return customCommand || "";
  }
}
