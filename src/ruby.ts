import { exec } from "child_process";
import { promisify } from "util";
import { readFile } from "fs/promises";

import * as vscode from "vscode";

const asyncExec = promisify(exec);

export class Ruby {
  public rubyVersion?: string;
  public yjitEnabled?: boolean;
  private workingFolder: string;
  private versionManager?: string;

  constructor() {
    this.workingFolder = vscode.workspace.workspaceFolders![0].uri.fsPath;
  }

  async activateRuby() {
    this.versionManager = vscode.workspace
      .getConfiguration("rubyLsp")
      .get("rubyVersionManager")!;

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
          await this.delay(500);
          break;
      }

      await this.fetchRubyInfo();
    } catch (error: any) {
      vscode.window.showErrorMessage(
        `Failed to activate ${this.versionManager} environment: ${error.message}`
      );
    }
  }

  private async activateShadowenv() {
    await vscode.extensions
      .getExtension("shopify.vscode-shadowenv")
      ?.activate();
  }

  private async activateChruby() {
    const rubyVersion = await this.readRubyVersion();
    await this.activate(`chruby-exec "${rubyVersion}" -- ruby`);
  }

  private async activate(ruby: string) {
    const result = await asyncExec(
      // eslint-disable-next-line no-process-env
      `${process.env.SHELL} -lic '${ruby} --disable-gems -rjson -e "puts JSON.dump(ENV.to_h)"'`,
      { cwd: this.workingFolder }
    );

    // eslint-disable-next-line no-process-env
    process.env = JSON.parse(result.stdout);
  }

  private async fetchRubyInfo() {
    const rubyInfo = await asyncExec(
      "ruby --disable-gems -e 'puts \"#{RUBY_VERSION},#{defined?(RubyVM::YJIT)}\"'"
    );

    const [rubyVersion, yjitIsDefined] = rubyInfo.stdout.trim().split(",");

    this.rubyVersion = rubyVersion;
    this.yjitEnabled = yjitIsDefined === "constant";
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

  private async delay(mseconds: number) {
    return new Promise((resolve) => {
      setTimeout(resolve, mseconds);
    });
  }
}
