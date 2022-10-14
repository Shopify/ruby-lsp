import { exec } from "child_process";
import { promisify } from "util";

import * as vscode from "vscode";

const asyncExec = promisify(exec);

export class Ruby {
  private workingFolder: string;
  private versionManager: string;

  constructor() {
    this.workingFolder = vscode.workspace.workspaceFolders![0].uri.fsPath;

    this.versionManager = vscode.workspace
      .getConfiguration("rubyLsp")
      .get("rubyVersionManager")!;
  }

  async activateRuby() {
    switch (this.versionManager) {
      case "chruby":
        await this.activateChruby();
        break;
      default:
        await this.activateShadowenv();
        break;
    }
  }

  async activateShadowenv() {
    await vscode.extensions
      .getExtension("shopify.vscode-shadowenv")
      ?.activate();
  }

  async activateChruby() {
    try {
      let shellProfilePath;
      // eslint-disable-next-line no-process-env
      const shell = process.env.SHELL?.split("/").pop();
      // eslint-disable-next-line no-process-env
      const home = process.env.HOME;

      switch (shell) {
        case "fish":
          shellProfilePath = `${home}/.config/fish/config.fish`;
          break;
        case "zsh":
          shellProfilePath = `${home}/.zshrc`;
          break;
        default:
          shellProfilePath = `${home}/.bashrc`;
          break;
      }

      const result = await asyncExec(
        `source ${shellProfilePath} &&
         chruby-exec ruby -rjson -e "puts JSON.dump(ENV.to_h)"`,
        { shell, cwd: this.workingFolder }
      );

      // eslint-disable-next-line no-process-env
      process.env = JSON.parse(result.stdout);
    } catch (error) {
      vscode.window.showErrorMessage(
        `Error when trying to activate chruby environment ${error}`
      );
    }
  }
}
