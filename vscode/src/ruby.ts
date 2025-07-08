/* eslint-disable no-process-env */
import path from "path";
import os from "os";

import * as vscode from "vscode";

import { asyncExec, RubyInterface } from "./common";
import { WorkspaceChannel } from "./workspaceChannel";
import { Shadowenv, UntrustedWorkspaceError } from "./ruby/shadowenv";
import { Chruby } from "./ruby/chruby";
import { VersionManager } from "./ruby/versionManager";
import { Mise } from "./ruby/mise";
import { RubyInstaller } from "./ruby/rubyInstaller";
import { Rbenv } from "./ruby/rbenv";
import { Rvm } from "./ruby/rvm";
import { None } from "./ruby/none";
import { Custom } from "./ruby/custom";
import { Asdf } from "./ruby/asdf";

async function detectMise() {
  const possiblePaths = [
    vscode.Uri.joinPath(vscode.Uri.file(os.homedir()), ".local", "bin", "mise"),
    vscode.Uri.joinPath(vscode.Uri.file("/"), "opt", "homebrew", "bin", "mise"),
    vscode.Uri.joinPath(vscode.Uri.file("/"), "usr", "bin", "mise"),
  ];

  for (const possiblePath of possiblePaths) {
    try {
      await vscode.workspace.fs.stat(possiblePath);
      return true;
    } catch (error: any) {
      // Continue looking
    }
  }

  return false;
}

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

export interface ManagerConfiguration {
  identifier: ManagerIdentifier;
}

export class Ruby implements RubyInterface {
  public rubyVersion?: string;
  // This property indicates that Ruby has been compiled with YJIT support and that we're running on a Ruby version
  // where it will be activated, either by the extension or by the server
  public yjitEnabled?: boolean;
  readonly gemPath: string[] = [];
  private readonly workspaceFolder: vscode.WorkspaceFolder;
  #versionManager: ManagerConfiguration = vscode.workspace
    .getConfiguration("rubyLsp")
    .get<ManagerConfiguration>("rubyVersionManager")!;

  private readonly shell = process.env.SHELL?.replace(/(\s+)/g, "\\$1");
  private _env: NodeJS.ProcessEnv = {};
  private _error = false;
  private readonly context: vscode.ExtensionContext;
  private readonly customBundleGemfile?: string;
  private readonly outputChannel: WorkspaceChannel;
  private readonly telemetry: vscode.TelemetryLogger;

  constructor(
    context: vscode.ExtensionContext,
    workspaceFolder: vscode.WorkspaceFolder,
    outputChannel: WorkspaceChannel,
    telemetry: vscode.TelemetryLogger,
  ) {
    this.context = context;
    this.workspaceFolder = workspaceFolder;
    this.outputChannel = outputChannel;
    this.telemetry = telemetry;

    const customBundleGemfile: string = vscode.workspace.getConfiguration("rubyLsp").get("bundleGemfile")!;

    if (customBundleGemfile.length > 0) {
      this.customBundleGemfile = path.isAbsolute(customBundleGemfile)
        ? customBundleGemfile
        : path.resolve(path.join(this.workspaceFolder.uri.fsPath, customBundleGemfile));
    }
  }

  get versionManager(): ManagerConfiguration {
    return this.#versionManager;
  }

  private set versionManager(versionManager: ManagerConfiguration | ManagerIdentifier) {
    if (typeof versionManager === "string") {
      this.#versionManager.identifier = versionManager;
    } else {
      this.#versionManager = versionManager;
    }
  }

  get env() {
    return this._env;
  }

  get error() {
    return this._error;
  }

  async activateRuby(
    versionManager: ManagerConfiguration = vscode.workspace
      .getConfiguration("rubyLsp")
      .get<ManagerConfiguration>("rubyVersionManager")!,
  ) {
    this.versionManager = versionManager;
    this._error = false;

    const workspaceRubyPath = await this.cachedWorkspaceRubyPath();

    if (workspaceRubyPath) {
      // If a workspace specific Ruby path is configured, then we use that to activate the environment
      await this.runActivation(
        new None(
          this.workspaceFolder,
          this.outputChannel,
          this.context,
          this.manuallySelectRuby.bind(this),
          workspaceRubyPath,
        ),
      );
    } else {
      // If the version manager is auto, discover the actual manager before trying to activate anything
      if (this.versionManager.identifier === ManagerIdentifier.Auto) {
        await this.discoverVersionManager();
        this.outputChannel.info(`Discovered version manager ${this.versionManager.identifier}`);
      }

      try {
        await this.runManagerActivation();
      } catch (error: any) {
        if (!(error instanceof UntrustedWorkspaceError)) {
          this.telemetry.logError(error, {
            appType: "extension",
            appVersion: this.context.extension.packageJSON.version,
            versionManager: this.versionManager.identifier,
            workspace: new vscode.TelemetryTrustedValue(this.workspaceFolder.name),
          });
        }

        // If an error occurred and a global Ruby path is configured, then we can try to fallback to that
        const globalRubyPath = vscode.workspace
          .getConfiguration("rubyLsp")
          .get<string | undefined>("rubyExecutablePath");

        if (globalRubyPath) {
          await this.runActivation(
            new None(
              this.workspaceFolder,
              this.outputChannel,
              this.context,
              this.manuallySelectRuby.bind(this),
              globalRubyPath,
            ),
          );
        } else {
          this._error = true;

          // When running tests, we need to throw the error or else activation may silently fail and it's very difficult
          // to debug
          if (this.context.extensionMode === vscode.ExtensionMode.Test) {
            throw error;
          }

          await this.handleRubyError(error.message);
        }
      }
    }

    if (!this.error) {
      this.fetchRubyVersionInfo();
      await this.setupBundlePath();
    }
  }

  async manuallySelectRuby() {
    const manualSelection = await vscode.window.showInformationMessage(
      "Configure global or workspace specific fallback for the Ruby LSP?",
      "global",
      "workspace",
      "clear previous workspace selection",
    );

    if (!manualSelection) {
      return;
    }

    if (manualSelection === "clear previous workspace selection") {
      await this.context.workspaceState.update(`rubyLsp.workspaceRubyPath.${this.workspaceFolder.name}`, undefined);
      return this.activateRuby();
    }

    const selection = await vscode.window.showOpenDialog({
      title: `Select Ruby binary path for ${manualSelection} configuration`,
      openLabel: "Select Ruby binary",
      canSelectMany: false,
    });

    if (!selection) {
      return;
    }

    const selectedPath = selection[0].fsPath;

    if (manualSelection === "global") {
      await vscode.workspace.getConfiguration("rubyLsp").update("rubyExecutablePath", selectedPath, true);
    } else {
      // We must update the cached Ruby path for this workspace if the user decided to change it
      await this.context.workspaceState.update(`rubyLsp.workspaceRubyPath.${this.workspaceFolder.name}`, selectedPath);
    }

    return this.activateRuby();
  }

  mergeComposedEnvironment(env: Record<string, string>) {
    this._env = { ...this._env, ...env };
  }

  private async runActivation(manager: VersionManager) {
    const { env, version, yjit, gemPath } = await manager.activate();
    const [major, minor, _patch] = version.split(".").map(Number);

    this.sanitizeEnvironment(env);

    if (this.context.extensionMode !== vscode.ExtensionMode.Test) {
      // We need to set the process environment too to make other extensions such as Sorbet find the right Ruby paths
      process.env = env;
    }

    this._env = env;
    this.rubyVersion = version;
    this.yjitEnabled = (yjit && major > 3) || (major === 3 && minor >= 2);
    this.gemPath.push(...gemPath);
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

  // Deletes environment variables that are known to cause issues for launching the Ruby LSP. For example, GC tuning
  // variables or verbose settings
  private sanitizeEnvironment(env: NodeJS.ProcessEnv) {
    // Delete all GC tuning variables
    Object.keys(env).forEach((key) => {
      if (key.startsWith("RUBY_GC")) {
        delete env[key];
      }
    });

    // Delete verbose or debug related settings. These often make Bundler or other dependencies print things to STDOUT,
    // which breaks the client/server communication
    delete env.VERBOSE;
    delete env.DEBUG;
  }

  private async runManagerActivation() {
    switch (this.versionManager.identifier) {
      case ManagerIdentifier.Asdf:
        await this.runActivation(
          new Asdf(this.workspaceFolder, this.outputChannel, this.context, this.manuallySelectRuby.bind(this)),
        );
        break;
      case ManagerIdentifier.Chruby:
        await this.runActivation(
          new Chruby(this.workspaceFolder, this.outputChannel, this.context, this.manuallySelectRuby.bind(this)),
        );
        break;
      case ManagerIdentifier.Rbenv:
        await this.runActivation(
          new Rbenv(this.workspaceFolder, this.outputChannel, this.context, this.manuallySelectRuby.bind(this)),
        );
        break;
      case ManagerIdentifier.Rvm:
        await this.runActivation(
          new Rvm(this.workspaceFolder, this.outputChannel, this.context, this.manuallySelectRuby.bind(this)),
        );
        break;
      case ManagerIdentifier.Mise:
        await this.runActivation(
          new Mise(this.workspaceFolder, this.outputChannel, this.context, this.manuallySelectRuby.bind(this)),
        );
        break;
      case ManagerIdentifier.RubyInstaller:
        await this.runActivation(
          new RubyInstaller(this.workspaceFolder, this.outputChannel, this.context, this.manuallySelectRuby.bind(this)),
        );
        break;
      case ManagerIdentifier.Custom:
        await this.runActivation(
          new Custom(this.workspaceFolder, this.outputChannel, this.context, this.manuallySelectRuby.bind(this)),
        );
        break;
      case ManagerIdentifier.None:
        await this.runActivation(
          new None(this.workspaceFolder, this.outputChannel, this.context, this.manuallySelectRuby.bind(this)),
        );
        break;
      default:
        await this.runActivation(
          new Shadowenv(this.workspaceFolder, this.outputChannel, this.context, this.manuallySelectRuby.bind(this)),
        );
        break;
    }
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
      throw new Error(`The configured bundle gemfile ${this.customBundleGemfile} does not exist`);
    }
  }

  private async discoverVersionManager() {
    // For shadowenv, it wouldn't be enough to check for the executable's existence. We need to check if the project has
    // created a .shadowenv.d folder
    try {
      await vscode.workspace.fs.stat(vscode.Uri.joinPath(this.workspaceFolder.uri, ".shadowenv.d"));
      this.versionManager.identifier = ManagerIdentifier.Shadowenv;
      return;
    } catch (error: any) {
      // If .shadowenv.d doesn't exist, then we check the other version managers
    }

    const managers = [ManagerIdentifier.Chruby, ManagerIdentifier.Rbenv, ManagerIdentifier.Rvm, ManagerIdentifier.Asdf];

    for (const tool of managers) {
      const exists = await this.toolExists(tool);

      if (exists) {
        this.versionManager = tool;
        return;
      }
    }

    if (await detectMise()) {
      this.versionManager = ManagerIdentifier.Mise;
      return;
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

      this.outputChannel.info(`Checking if ${tool} is available on the path with command: ${command}`);

      await asyncExec(command, {
        cwd: this.workspaceFolder.uri.fsPath,
        timeout: 1000,
      });
      return true;
    } catch {
      return false;
    }
  }

  private async handleRubyError(message: string) {
    const answer = await vscode.window.showErrorMessage(
      `Automatic Ruby environment activation with ${this.versionManager.identifier} failed: ${message}`,
      "Retry",
      "Select Ruby manually",
    );

    // If the user doesn't answer anything, we can just return. The error property was already set to true and we won't
    // try to launch the LSP
    if (!answer) {
      return;
    }

    // For retrying, reload the entire window to get rid of any state
    if (answer === "Retry") {
      await vscode.commands.executeCommand("workbench.action.reloadWindow");
    }

    return this.manuallySelectRuby();
  }

  private async cachedWorkspaceRubyPath() {
    const workspaceRubyPath = this.context.workspaceState.get<string | undefined>(
      `rubyLsp.workspaceRubyPath.${this.workspaceFolder.name}`,
    );

    if (!workspaceRubyPath) {
      return undefined;
    }

    try {
      await vscode.workspace.fs.stat(vscode.Uri.file(workspaceRubyPath));
      return workspaceRubyPath;
    } catch (error: any) {
      // If the user selected a Ruby path and then uninstalled it, we need to clear the the cached path
      this.context.workspaceState.update(`rubyLsp.workspaceRubyPath.${this.workspaceFolder.name}`, undefined);
      return undefined;
    }
  }
}
