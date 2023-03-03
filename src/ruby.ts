import { exec } from "child_process";
import { promisify } from "util";
import { readFile } from "fs/promises";

import * as vscode from "vscode";

const asyncExec = promisify(exec);

export enum VersionManager {
  Asdf = "asdf",
  Chruby = "chruby",
  Rbenv = "rbenv",
  Rvm = "rvm",
  Shadowenv = "shadowenv",
  None = "none",
}

export class Ruby {
  public rubyVersion?: string;
  public yjitEnabled?: boolean;
  public supportsYjit?: boolean;
  private workingFolder: string;
  private versionManager?: VersionManager;

  constructor() {
    this.workingFolder = vscode.workspace.workspaceFolders![0].uri.fsPath;
  }

  async activateRuby() {
    this.versionManager = vscode.workspace
      .getConfiguration("rubyLsp")
      .get("rubyVersionManager")!;

    try {
      switch (this.versionManager) {
        case VersionManager.Asdf:
          await this.activate("asdf exec ruby");
          break;
        case VersionManager.Chruby:
          await this.activateChruby();
          break;
        case VersionManager.Rbenv:
          await this.activate("rbenv exec ruby");
          break;
        case VersionManager.Rvm:
          await this.activate("rvm-auto-ruby");
          break;
        case VersionManager.None:
          break;
        default:
          await this.activateShadowenv();
          await this.delay(500);
          break;
      }

      await this.fetchRubyInfo();
    } catch (error: any) {
      await vscode.window.showErrorMessage(
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
      `${process.env.SHELL} -lic '${ruby} --disable-gems -rjson -e "puts %Q{RUBY_ENV_ACTIVATE#{JSON.dump(ENV.to_h)}RUBY_ENV_ACTIVATE}"'`,
      { cwd: this.workingFolder }
    );

    const envJson = result.stdout.match(
      /RUBY_ENV_ACTIVATE(.*)RUBY_ENV_ACTIVATE/
    )![1];
    // eslint-disable-next-line no-process-env
    process.env = JSON.parse(envJson);
  }

  private async fetchRubyInfo() {
    const rubyInfo = await asyncExec(
      "ruby --disable-gems -e 'puts \"#{RUBY_VERSION},#{defined?(RubyVM::YJIT)}\"'"
    );

    const [rubyVersion, yjitIsDefined] = rubyInfo.stdout.trim().split(",");

    this.rubyVersion = rubyVersion;
    this.yjitEnabled = yjitIsDefined === "constant";

    const [major, minor, _patch] = this.rubyVersion.split(".").map(Number);
    this.supportsYjit = this.yjitEnabled && [major, minor] >= [3, 2];
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
