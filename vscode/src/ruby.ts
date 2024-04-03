/* eslint-disable no-process-env */
import path from "path";
import os from "os";

import * as vscode from "vscode";

import { asyncExec, RubyInterface } from "./common";
import { WorkspaceChannel } from "./workspaceChannel";
import { Shadowenv } from "./ruby/shadowenv";
import { Chruby } from "./ruby/chruby";
import { VersionManager } from "./ruby/versionManager";
import { Mise } from "./ruby/mise";
import { RubyInstaller } from "./ruby/rubyInstaller";
import { Rbenv } from "./ruby/rbenv";
import { Rvm } from "./ruby/rvm";
import { None } from "./ruby/none";
import { Custom } from "./ruby/custom";

export enum ManagerIdentifier {
  Asdf = "asdf",
  Auto = "auto",
  Chruby = "chruby",
  Rbenv = "rbenv",
  Rvm = "rvm",
  Shadowenv = "shadowenv",
  Mise = "mise",
  RubyInstaller = "rubyInstaller",
  None = "none",
  Custom = "custom",
}

export class Ruby implements RubyInterface {
  public rubyVersion?: string;
  // This property indicates that Ruby has been compiled with YJIT support and that we're running on a Ruby version
  // where it will be activated, either by the extension or by the server
  public yjitEnabled?: boolean;
  private readonly workspaceFolder: vscode.WorkspaceFolder;
  #versionManager?: ManagerIdentifier;

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

  private set versionManager(versionManager: ManagerIdentifier | undefined) {
    this.#versionManager = versionManager;
  }

  get env() {
    return this._env;
  }

  get error() {
    return this._error;
  }

  async activateRuby(
    versionManager: ManagerIdentifier = vscode.workspace
      .getConfiguration("rubyLsp")
      .get("rubyVersionManager")!,
  ) {
    this.versionManager = versionManager;

    // If the version manager is auto, discover the actual manager before trying to activate anything
    if (this.versionManager === ManagerIdentifier.Auto) {
      await this.discoverVersionManager();
      this.outputChannel.info(
        `Discovered version manager ${this.versionManager}`,
      );
    }

    try {
      switch (this.versionManager) {
        case ManagerIdentifier.Asdf:
          await this.activate("asdf exec ruby");
          break;
        case ManagerIdentifier.Chruby:
          await this.runActivation(
            new Chruby(this.workspaceFolder, this.outputChannel),
          );
          break;
        case ManagerIdentifier.Rbenv:
          await this.runActivation(
            new Rbenv(this.workspaceFolder, this.outputChannel),
          );
          break;
        case ManagerIdentifier.Rvm:
          await this.runActivation(
            new Rvm(this.workspaceFolder, this.outputChannel),
          );
          break;
        case ManagerIdentifier.Mise:
          await this.runActivation(
            new Mise(this.workspaceFolder, this.outputChannel),
          );
          break;
        case ManagerIdentifier.RubyInstaller:
          await this.runActivation(
            new RubyInstaller(this.workspaceFolder, this.outputChannel),
          );
          break;
        case ManagerIdentifier.Custom:
          await this.runActivation(
            new Custom(this.workspaceFolder, this.outputChannel),
          );
          break;
        case ManagerIdentifier.None:
          await this.runActivation(
            new None(this.workspaceFolder, this.outputChannel),
          );
          break;
        default:
          await this.runActivation(
            new Shadowenv(this.workspaceFolder, this.outputChannel),
          );
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

  private async runActivation(manager: VersionManager) {
    const { env, version, yjit } = await manager.activate();
    const [major, minor, _patch] = version.split(".").map(Number);

    // We need to set the process environment too to make other extensions such as Sorbet find the right Ruby paths
    process.env = env;
    this._env = env;
    this.rubyVersion = version;
    this.yjitEnabled = (yjit && major > 3) || (major === 3 && minor >= 2);
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
      (rubyInfo.yjit === "constant" && major > 3) ||
      (major === 3 && minor >= 2);
  }

  // Fetch information related to the Ruby version. This can only be invoked after activation, so that `rubyVersion` is
  // set
  private fetchRubyVersionInfo() {
    const [major, minor, _patch] = this.rubyVersion!.split(".").map(Number);

    if (major < 3) {
      throw new Error(
        `The Ruby LSP requires Ruby 3.0 or newer to run. This project is using ${this.rubyVersion}. \
        [See alternatives](https://github.com/Shopify/ruby-lsp/blob/main/vscode/README.md#ruby-version-requirement)`,
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

    try {
      await vscode.workspace.fs.stat(vscode.Uri.file(this.customBundleGemfile));
      this._env.BUNDLE_GEMFILE = this.customBundleGemfile;
    } catch (error: any) {
      throw new Error(
        `The configured bundle gemfile ${this.customBundleGemfile} does not exist`,
      );
    }
  }

  private async discoverVersionManager() {
    // For shadowenv, it wouldn't be enough to check for the executable's existence. We need to check if the project has
    // created a .shadowenv.d folder
    try {
      await vscode.workspace.fs.stat(
        vscode.Uri.joinPath(this.workspaceFolder.uri, ".shadowenv.d"),
      );
      this.versionManager = ManagerIdentifier.Shadowenv;
      return;
    } catch (error: any) {
      // If .shadowenv.d doesn't exist, then we check the other version managers
    }

    const managers = [
      ManagerIdentifier.Asdf,
      ManagerIdentifier.Chruby,
      ManagerIdentifier.Rbenv,
      ManagerIdentifier.Rvm,
    ];

    for (const tool of managers) {
      const exists = await this.toolExists(tool);

      if (exists) {
        this.versionManager = tool;
        return;
      }
    }

    try {
      await vscode.workspace.fs.stat(
        vscode.Uri.joinPath(
          vscode.Uri.file(os.homedir()),
          ".local",
          "bin",
          "mise",
        ),
      );
      this.versionManager = ManagerIdentifier.Mise;
      return;
    } catch (error: any) {
      // If the Mise binary doesn't exist, then continue checking
    }

    if (os.platform() === "win32") {
      this.versionManager = ManagerIdentifier.RubyInstaller;
      return;
    }

    // If we can't find a version manager, just return None
    this.versionManager = ManagerIdentifier.None;
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
}
