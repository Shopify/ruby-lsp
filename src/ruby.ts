import { exec } from "child_process";
import { promisify } from "util";
import { readFile } from "fs/promises";

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
    try {
      switch (this.versionManager) {
        case "asdf":
          await this.activate("asdf exec ruby");
          break;
        case "chruby":
          await this.activateChruby();
          break;
        case "rbenv":
          await this.activate("rbenv exec ruby");
          break;
        case "rvm":
          await this.activate("rvm-auto-ruby");
          break;
        default:
          await this.activateShadowenv();
          break;
      }

      this.displayRubyVersion();
    } catch (error: any) {
      vscode.window.showErrorMessage(
        `Failed to activate ${this.versionManager} environment: ${error.message}`
      );
    }
  }

  async activateShadowenv() {
    await vscode.extensions
      .getExtension("shopify.vscode-shadowenv")
      ?.activate();
  }

  async activateChruby() {
    const rubyVersion = await this.readRubyVersion();
    await this.activate(`chruby-exec "${rubyVersion}" -- ruby`);
  }

  async activate(ruby: string) {
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
      `source ${shellProfilePath} > /dev/null 2>&1 && ${ruby} -rjson -e "puts JSON.dump(ENV.to_h)"`,
      { shell, cwd: this.workingFolder }
    );

    // eslint-disable-next-line no-process-env
    process.env = JSON.parse(result.stdout);
  }

  private async displayRubyVersion() {
    const rubyVersion = await asyncExec('ruby -e "puts RUBY_VERSION"');
    vscode.window.setStatusBarMessage(`Ruby ${rubyVersion.stdout.trim()}`);
  }

  private async readRubyVersion() {
    try {
      const version = await readFile(
        `${this.workingFolder}/.ruby-version`,
        "utf8"
      );

      return version.trim();
    } catch (error: any) {
      if (error.code === "ENOENT") {
        throw new Error("No .ruby-version file was found");
      } else {
        throw error;
      }
    }
  }
}
