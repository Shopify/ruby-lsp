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
  #versionManager?: VersionManager;
  // eslint-disable-next-line no-process-env
  private shell = process.env.SHELL;
  private _env: NodeJS.ProcessEnv = {};
  private _error = false;

  constructor(
    workingFolder = vscode.workspace.workspaceFolders![0].uri.fsPath
  ) {
    this.workingFolder = workingFolder;
  }

  get versionManager() {
    return this.#versionManager;
  }

  private set versionManager(versionManager: VersionManager | undefined) {
    this.#versionManager = versionManager;
  }

  get env() {
    return this._env;
  }

  get error() {
    return this._error;
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
          break;
      }

      await this.fetchRubyInfo();
      this.deleteGcEnvironmentVariables();
      this.setupBundlePath();
      this._error = false;
    } catch (error: any) {
      this._error = true;

      await vscode.window.showErrorMessage(
        `Failed to activate ${this.versionManager} environment: ${error.message}`
      );
    }
  }

  private async activateShadowenv() {
    const extension = vscode.extensions.getExtension(
      "shopify.vscode-shadowenv"
    );

    if (!extension) {
      throw new Error(
        "The Ruby LSP version manager is configured to be shadowenv, but the shadowenv extension is not installed"
      );
    }

    if (!fs.existsSync(path.join(this.workingFolder, ".shadowenv.d"))) {
      throw new Error(
        "The Ruby LSP version manager is configured to be shadowenv, \
        but no .shadowenv.d directory was found in the workspace"
      );
    }

    await extension.activate();
    await this.delay(500);
    // eslint-disable-next-line no-process-env
    this._env = { ...process.env };
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

    if ((major === 2 && minor < 7) || major < 2) {
      throw new Error(
        "The Ruby LSP requires Ruby 2.7 or newer to run. Please upgrade your Ruby version"
      );
    }

    this.supportsYjit =
      this.yjitEnabled && (major > 3 || (major === 3 && minor >= 2));

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
    if (path.basename(this.workingFolder) !== "ruby-lsp") {
      this._env.BUNDLE_GEMFILE = path.join(
        this.workingFolder,
        ".ruby-lsp",
        "Gemfile"
      );

      // We must use the default system path for bundler in case someone has BUNDLE_PATH configured. Otherwise, we end
      // up with all gems installed inside of the `.ruby-lsp` folder, which may lead to all sorts of errors
      this._env.BUNDLE_PATH__SYSTEM = "true";
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
