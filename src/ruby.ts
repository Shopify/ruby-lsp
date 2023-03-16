import { exec } from "child_process";
import { promisify } from "util";
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
  private _env: NodeJS.ProcessEnv = {};

  constructor(
    workingFolder = vscode.workspace.workspaceFolders![0].uri.fsPath
  ) {
    this.workingFolder = workingFolder;
  }

  get env() {
    return this._env;
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
          // eslint-disable-next-line no-process-env
          this._env = { ...process.env };
          break;
      }

      await this.fetchRubyInfo();
      this.deleteGcEnvironmentVariables();
      this.setupBundlePath();
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
    await this.activate(`chruby "${rubyVersion}" && ruby`);
  }

  private async activate(ruby: string) {
    const result = await asyncExec(
      `${this.shell} -lic '${ruby} --disable-gems -rjson -e "printf(%{RUBY_ENV_ACTIVATE%sRUBY_ENV_ACTIVATE}, JSON.dump(ENV.to_h))"'`,
      { cwd: this.workingFolder }
    );

    const envJson = result.stdout.match(
      /RUBY_ENV_ACTIVATE(.*)RUBY_ENV_ACTIVATE/
    )![1];

    this._env = JSON.parse(envJson);
  }

  private async fetchRubyInfo() {
    const rubyInfo = await asyncExec(
      "ruby --disable-gems -e 'puts \"#{RUBY_VERSION},#{defined?(RubyVM::YJIT)}\"'",
      { env: this._env }
    );

    const [rubyVersion, yjitIsDefined] = rubyInfo.stdout.trim().split(",");

    this.rubyVersion = rubyVersion;
    this.yjitEnabled = yjitIsDefined === "constant";

    const [major, minor, _patch] = this.rubyVersion.split(".").map(Number);
    this.supportsYjit = this.yjitEnabled && [major, minor] >= [3, 2];

    const useYjit = vscode.workspace.getConfiguration("rubyLsp").get("yjit");

    if (this.supportsYjit && useYjit) {
      // RUBYOPT may be empty or it may contain bundler paths. In the second case, we must concat to avoid accidentally
      // removing the paths from the env variable
      if (this._env.RUBYOPT) {
        this._env.RUBYOPT.concat(" --yjit");
      } else {
        this._env.RUBYOPT = "--yjit";
      }
    }
  }

  private deleteGcEnvironmentVariables() {
    Object.keys(this._env).forEach((key) => {
      if (key.startsWith("RUBY_GC")) {
        delete this._env[key];
      }
    });
  }

  private setupBundlePath() {
    // Use our custom Gemfile to allow RuboCop and extensions to work without having to add ruby-lsp to the bundle. Note
    // that we can't do this for the ruby-lsp repository itself otherwise the gem is activated twice
    if (!this.workingFolder.endsWith("ruby-lsp")) {
      this._env.BUNDLE_GEMFILE = path.join(
        this.workingFolder,
        ".ruby-lsp",
        "Gemfile"
      );
    }
  }

  private async readRubyVersion() {
    let dir = this.workingFolder;

    while (fs.existsSync(dir)) {
      const versionFile = path.join(dir, ".ruby-version");

      if (fs.existsSync(versionFile)) {
        const version = fs.readFileSync(versionFile, "utf8");
        const trimmedVersion = version.trim();

        if (trimmedVersion !== "") {
          return trimmedVersion;
        }
      }

      const parent = path.dirname(dir);

      // When we hit the root path (e.g. /), parent will be the same as dir.
      // We don't want to loop forever in this case, so we break out of the loop.
      if (parent === dir) {
        break;
      }

      dir = parent;
    }

    throw new Error("No .ruby-version file was found");
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
