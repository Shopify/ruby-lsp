import { exec } from "child_process";
import { promisify } from "util";
import { readFile } from "fs/promises";
import path from "path";
import fs from "fs";

import * as vscode from "vscode";

const asyncExec = promisify(exec);

export enum VersionManager {
  Asdf = "asdf",
  Auto = "auto",
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
  // eslint-disable-next-line no-process-env
  private shell = process.env.SHELL;

  constructor() {
    this.workingFolder = vscode.workspace.workspaceFolders![0].uri.fsPath;
  }

  async activateRuby() {
    this.versionManager = vscode.workspace
      .getConfiguration("rubyLsp")
      .get("rubyVersionManager")!;

    // If the version manager is auto, discover the actual manager before trying to activate anything
    if (this.versionManager === VersionManager.Auto) {
      await this.discoverVersionManager();
    }

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
      `${this.shell} -lic '${ruby} --disable-gems -rjson -e "printf(%{RUBY_ENV_ACTIVATE%sRUBY_ENV_ACTIVATE}, JSON.dump(ENV.to_h))"'`,
      { cwd: this.workingFolder }
    );

    const envJson = result.stdout.match(
      /RUBY_ENV_ACTIVATE(.*)RUBY_ENV_ACTIVATE/
    )![1];
    // eslint-disable-next-line no-process-env
    process.env = JSON.parse(envJson);
  }

  private async fetchRubyInfo() {
    if (this.versionManager === VersionManager.Auto) {
      return;
    }

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

  private async discoverVersionManager() {
    // For shadowenv, it wouldn't be enough to check for the executable's existence. We need to check if the project has
    // created a .shadowenv.d folder
    if (fs.existsSync(path.join(this.workingFolder, ".shadowenv.d"))) {
      this.versionManager = VersionManager.Shadowenv;
      return;
    }

    const managers = [
      VersionManager.Asdf,
      VersionManager.Chruby,
      VersionManager.Rbenv,
      VersionManager.Rvm,
    ];

    for (const tool of managers) {
      const exists = await this.toolExists(tool);

      if (exists) {
        this.versionManager = tool;
        return;
      }
    }

    // If we can't find a version manager, just return None
    this.versionManager = VersionManager.None;
  }

  private async toolExists(tool: string) {
    try {
      await asyncExec(`${this.shell} -lic '${tool} --version'`);
      return true;
    } catch {
      return false;
    }
  }

  private async delay(mseconds: number) {
    return new Promise((resolve) => {
      setTimeout(resolve, mseconds);
    });
  }
}
