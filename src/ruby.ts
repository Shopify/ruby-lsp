import { exec } from "child_process";
import { promisify } from "util";
import * as fs from "fs";

import * as vscode from "vscode";

const asyncExec = promisify(exec);
const asyncReadFile = promisify(fs.readFile);

export class Ruby {
  private workingFolder: string;
  private managerConfiguration: { [key: string]: string };

  constructor() {
    this.workingFolder = vscode.workspace.workspaceFolders![0].uri.fsPath;

    this.managerConfiguration = vscode.workspace
      .getConfiguration("rubyLsp")
      .get("rubyVersionManager")!;
  }

  async activateRuby() {
    switch (this.managerConfiguration.manager) {
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
    if (!fs.existsSync(`${this.workingFolder}/.ruby-version`)) {
      vscode.window.showErrorMessage(
        "Attempted to activate chruby environment, but no .ruby-version file was found."
      );
      return;
    }

    if (!fs.existsSync(this.managerConfiguration.path)) {
      vscode.window.showErrorMessage(
        `Attempted to activate chruby environment, but the path provided does not exist (${this.managerConfiguration.path}).`
      );
      return;
    }

    const rubyVersion = await asyncReadFile(
      `${this.workingFolder}/.ruby-version`
    );

    try {
      const result = await asyncExec(
        `source ${this.managerConfiguration.path} &&
         chruby "${rubyVersion.toString().trim()}" &&
         ruby -rjson -e "puts JSON.dump(ENV.to_h)"`
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
