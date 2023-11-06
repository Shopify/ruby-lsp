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
  Custom = "custom",
}

export class Ruby {
  public rubyVersion?: string;
  public yjitEnabled?: boolean;
  public supportsYjit?: boolean;
  private readonly workingFolder: string;
  #versionManager?: VersionManager;
  // eslint-disable-next-line no-process-env
  private readonly shell = process.env.SHELL;
  private _env: NodeJS.ProcessEnv = {};
  private _error = false;
  private readonly context: vscode.ExtensionContext;
  private readonly customBundleGemfile?: string;
  private readonly cwd: string;
  private readonly outputChannel: vscode.OutputChannel;

  constructor(
    context: vscode.ExtensionContext,
    outputChannel: vscode.OutputChannel,
    workingFolder = vscode.workspace.workspaceFolders![0].uri.fsPath,
  ) {
    this.context = context;
    this.workingFolder = workingFolder;
    this.outputChannel = outputChannel;

    const customBundleGemfile: string = vscode.workspace
      .getConfiguration("rubyLsp")
      .get("bundleGemfile")!;

    if (customBundleGemfile.length > 0) {
      this.customBundleGemfile = path.isAbsolute(customBundleGemfile)
        ? customBundleGemfile
        : path.resolve(path.join(this.workingFolder, customBundleGemfile));
    }

    this.cwd = this.customBundleGemfile
      ? path.dirname(this.customBundleGemfile)
      : this.workingFolder;
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
      this.outputChannel.appendLine(
        `Ruby LSP> Discovered version manager ${this.versionManager}`,
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

      await this.fetchRubyInfo();
      this.deleteGcEnvironmentVariables();
      this.setupBundlePath();
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
    if (!fs.existsSync(path.join(this.workingFolder, ".shadowenv.d"))) {
      throw new Error(
        "The Ruby LSP version manager is configured to be shadowenv, \
        but no .shadowenv.d directory was found in the workspace",
      );
    }

    const result = await asyncExec("shadowenv hook --json 1>&2", {
      cwd: this.cwd,
    });

    if (result.stderr.trim() === "") {
      result.stderr = "{ }";
    }
    // eslint-disable-next-line no-process-env
    const env = { ...process.env, ...JSON.parse(result.stderr).exported };

    // If the configurations under `.shadowenv.d/` point to a Ruby version that is not installed, shadowenv will still
    // return the complete environment without throwing any errors. Here, we check to see if the RUBY_ROOT returned by
    // shadowenv exists. If it doens't, then it's likely that the Ruby version configured is not installed
    if (!fs.existsSync(env.RUBY_ROOT)) {
      throw new Error(
        `The Ruby version configured in .shadowenv.d is ${env.RUBY_VERSION}, \
        but the Ruby installation at ${env.RUBY_ROOT} does not exist`,
      );
    }

    // The only reason we set the process environment here is to allow other extensions that don't perform activation
    // work properly
    // eslint-disable-next-line no-process-env
    process.env = env;
    this._env = env;
  }

  private async activateChruby() {
    const rubyVersion = this.readRubyVersion();
    await this.activate(`chruby "${rubyVersion}" && ruby`);
  }

  private async activate(ruby: string) {
    let command = this.shell ? `${this.shell} -ic '` : "";
    command += `${ruby} -rjson -e "STDERR.printf(%{RUBY_ENV_ACTIVATE%sRUBY_ENV_ACTIVATE}, JSON.dump(ENV.to_h))"`;

    if (this.shell) {
      command += "'";
    }

    this.outputChannel.appendLine(
      `Ruby LSP> Trying to activate Ruby environment with command: ${command} inside directory: ${this.cwd}`,
    );

    const result = await asyncExec(command, { cwd: this.cwd });

    const envJson = /RUBY_ENV_ACTIVATE(.*)RUBY_ENV_ACTIVATE/.exec(
      result.stderr,
    )![1];

    this._env = JSON.parse(envJson);
  }

  private async fetchRubyInfo() {
    const rubyInfo = await asyncExec(
      "ruby -e 'STDERR.print(\"#{RUBY_VERSION},#{defined?(RubyVM::YJIT)}\")'",
      { env: this._env, cwd: this.cwd },
    );

    const [rubyVersion, yjitIsDefined] = rubyInfo.stderr.trim().split(",");

    this.rubyVersion = rubyVersion;
    this.yjitEnabled = yjitIsDefined === "constant";

    const [major, minor, _patch] = this.rubyVersion.split(".").map(Number);

    if (major < 3) {
      throw new Error(
        `The Ruby LSP requires Ruby 3.0 or newer to run. This project is using ${this.rubyVersion}. \
        [See alternatives](https://github.com/Shopify/vscode-ruby-lsp?tab=readme-ov-file#ruby-version-requirement)`,
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
    // Some users like to define a completely separate Gemfile for development tools. We allow them to use
    // `rubyLsp.bundleGemfile` to configure that and need to inject it into the environment
    if (!this.customBundleGemfile) {
      return;
    }

    if (!fs.existsSync(this.customBundleGemfile)) {
      throw new Error(
        `The configured bundle gemfile ${this.customBundleGemfile} does not exist`,
      );
    }

    this._env.BUNDLE_GEMFILE = this.customBundleGemfile;
  }

  private readRubyVersion() {
    let dir = this.cwd;

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
      let command = this.shell ? `${this.shell} -ic '` : "";
      command += `${tool} --version`;

      if (this.shell) {
        command += "'";
      }

      this.outputChannel.appendLine(
        `Ruby LSP> Checking if ${tool} is available on the path with command: ${command}`,
      );

      await asyncExec(command, { cwd: this.workingFolder });
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
        See the [README](https://github.com/Shopify/vscode-ruby-lsp#custom-activation) for instructions.",
      );
    }

    await this.activate(`${customCommand} && ruby`);
  }
}
