import path from "path";
import fs from "fs/promises";

import * as vscode from "vscode";

import { asyncExec, pathExists, RubyInterface } from "./common";
import { WorkspaceChannel } from "./workspaceChannel";
import { Shadowenv } from "./ruby/shadowenv";

export enum VersionManager {
  Asdf = "asdf",
  Auto = "auto",
  Chruby = "chruby",
  Rbenv = "rbenv",
  Rvm = "rvm",
  Shadowenv = "shadowenv",
  None = "none",
  Custom = "custom",
}

export class Ruby implements RubyInterface {
  public rubyVersion?: string;
  // This property indicates that Ruby has been compiled with YJIT support and that we're running on a Ruby version
  // where it will be activated, either by the extension or by the server
  public yjitEnabled?: boolean;
  private readonly workspaceFolder: vscode.WorkspaceFolder;
  #versionManager?: VersionManager;
  // eslint-disable-next-line no-process-env
  private readonly shell = process.env.SHELL?.replace(/(\s+)/g, "\\$1");
  private _env: NodeJS.ProcessEnv = {};
  private _error = false;
  private readonly context: vscode.ExtensionContext;
  private readonly customBundleGemfile?: string;
  private readonly cwd: string;
  private readonly outputChannel: WorkspaceChannel;

  constructor(
    context: vscode.ExtensionContext,
    workspaceFolder: vscode.WorkspaceFolder,
    outputChannel: WorkspaceChannel,
  ) {
    this.context = context;
    this.workspaceFolder = workspaceFolder;
    this.outputChannel = outputChannel;

    const customBundleGemfile: string = vscode.workspace
      .getConfiguration("rubyLsp")
      .get("bundleGemfile")!;

    if (customBundleGemfile.length > 0) {
      this.customBundleGemfile = path.isAbsolute(customBundleGemfile)
        ? customBundleGemfile
        : path.resolve(
            path.join(this.workspaceFolder.uri.fsPath, customBundleGemfile),
          );
    }

    this.cwd = this.customBundleGemfile
      ? path.dirname(this.customBundleGemfile)
      : this.workspaceFolder.uri.fsPath;
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

  async activateRuby(
    versionManager: VersionManager = vscode.workspace
      .getConfiguration("rubyLsp")
      .get("rubyVersionManager")!,
  ) {
    this.versionManager = versionManager;

    // If the version manager is auto, discover the actual manager before trying to activate anything
    if (this.versionManager === VersionManager.Auto) {
      await this.discoverVersionManager();
      this.outputChannel.info(
        `Discovered version manager ${this.versionManager}`,
      );
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
        case VersionManager.Custom:
          await this.activateCustomRuby();
          break;
        case VersionManager.None:
          await this.activate("ruby");
          break;
        default:
          await this.activateShadowenv();
          break;
      }

      this.fetchRubyVersionInfo();
      this.deleteGcEnvironmentVariables();
      await this.setupBundlePath();
      this._error = false;
    } catch (error: any) {
      this._error = true;

      // When running tests, we need to throw the error or else activation may silently fail and it's very difficult to
      // debug
      if (this.context.extensionMode === vscode.ExtensionMode.Test) {
        throw error;
      }

      await vscode.window.showErrorMessage(
        `Failed to activate ${this.versionManager} environment: ${error.message}`,
      );
    }
  }

  private async activateShadowenv() {
    const shadowenv = new Shadowenv(this.workspaceFolder, this.outputChannel);
    const { env, version, yjit } = await shadowenv.activate();
    const [major, minor, _patch] = version.split(".").map(Number);

    // We need to set the process environment too to make other extensions such as Sorbet find the right Ruby paths
    // eslint-disable-next-line no-process-env
    process.env = env;
    this._env = env;
    this.rubyVersion = version;
    this.yjitEnabled = (yjit && major >= 3) || (major === 3 && minor >= 2);
  }

  private async activateChruby() {
    const rubyVersion = await this.readRubyVersion();
    await this.activate(`chruby "${rubyVersion}" && ruby`);
  }

  private async activate(ruby: string) {
    let command = this.shell ? `${this.shell} -i -c '` : "";

    // The Ruby activation script is intentionally written as an array that gets joined into a one liner because some
    // terminals cannot handle line breaks. Do not switch this to a multiline string or that will break activation for
    // those terminals
    const script = [
      "STDERR.printf(%{RUBY_ENV_ACTIVATE%sRUBY_ENV_ACTIVATE}, ",
      "JSON.dump({ env: ENV.to_h, ruby_version: RUBY_VERSION, yjit: defined?(RubyVM::YJIT) }))",
    ].join("");

    command += `${ruby} -rjson -e "${script}"`;

    if (this.shell) {
      command += "'";
    }

    this.outputChannel.info(
      `Trying to activate Ruby environment with command: ${command} inside directory: ${this.cwd}`,
    );

    const result = await asyncExec(command, { cwd: this.cwd });
    const rubyInfoJson = /RUBY_ENV_ACTIVATE(.*)RUBY_ENV_ACTIVATE/.exec(
      result.stderr,
    )![1];

    const rubyInfo = JSON.parse(rubyInfoJson);

    this._env = rubyInfo.env;
    this.rubyVersion = rubyInfo.ruby_version;

    const [major, minor, _patch] = rubyInfo.ruby_version.split(".").map(Number);
    this.yjitEnabled =
      (rubyInfo.yjit === "constant" && major >= 3) ||
      (major === 3 && minor >= 2);
  }

  // Fetch information related to the Ruby version. This can only be invoked after activation, so that `rubyVersion` is
  // set
  private fetchRubyVersionInfo() {
    const [major, minor, _patch] = this.rubyVersion!.split(".").map(Number);

    if (major < 3) {
      throw new Error(
        `The Ruby LSP requires Ruby 3.0 or newer to run. This project is using ${this.rubyVersion}. \
        [See alternatives](https://github.com/Shopify/ruby-lsp/blob/main/vscode/README.md \
        ?tab=readme-ov-file#ruby-version-requirement)`,
      );
    }

    // Starting with Ruby 3.3 the server enables YJIT itself
    if (this.yjitEnabled && major === 3 && minor === 2) {
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

  private async setupBundlePath() {
    // Some users like to define a completely separate Gemfile for development tools. We allow them to use
    // `rubyLsp.bundleGemfile` to configure that and need to inject it into the environment
    if (!this.customBundleGemfile) {
      return;
    }

    if (!(await pathExists(this.customBundleGemfile))) {
      throw new Error(
        `The configured bundle gemfile ${this.customBundleGemfile} does not exist`,
      );
    }

    this._env.BUNDLE_GEMFILE = this.customBundleGemfile;
  }

  private async readRubyVersion() {
    let dir = this.cwd;

    while (await pathExists(dir)) {
      const versionFile = path.join(dir, ".ruby-version");

      if (await pathExists(versionFile)) {
        const version = await fs.readFile(versionFile, "utf8");
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
    try {
      await vscode.workspace.fs.stat(
        vscode.Uri.joinPath(this.workspaceFolder.uri, ".shadowenv.d"),
      );
      this.versionManager = VersionManager.Shadowenv;
      return;
    } catch (error: any) {
      // If .shadowenv.d doesn't exist, then we check the other version managers
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
      let command = this.shell ? `${this.shell} -i -c '` : "";
      command += `${tool} --version`;

      if (this.shell) {
        command += "'";
      }

      this.outputChannel.info(
        `Checking if ${tool} is available on the path with command: ${command}`,
      );

      await asyncExec(command, {
        cwd: this.workspaceFolder.uri.fsPath,
        timeout: 1000,
      });
      return true;
    } catch {
      return false;
    }
  }

  private async activateCustomRuby() {
    const configuration = vscode.workspace.getConfiguration("rubyLsp");
    const customCommand: string | undefined =
      configuration.get("customRubyCommand");

    if (customCommand === undefined) {
      throw new Error(
        "The customRubyCommand configuration must be set when 'custom' is selected as the version manager. \
        See the [README](https://github.com/Shopify/ruby-lsp/blob/main/vscode/VERSION_MANAGERS.md) for instructions.",
      );
    }

    await this.activate(`${customCommand} && ruby`);
  }
}
