/* eslint-disable no-process-env */
import os from "os";
import path from "path";

import * as vscode from "vscode";

import { WorkspaceChannel } from "../workspaceChannel";

import {
  ActivationResult,
  VersionManager,
  ACTIVATION_SEPARATOR,
} from "./versionManager";

interface RubyVersion {
  engine?: string;
  version: string;
}

class RubyActivationCancellationError extends Error {}

// A tool to change the current Ruby version
// Learn more: https://github.com/postmodern/chruby
export class Chruby extends VersionManager {
  // Only public so that we can point to a different directory in tests
  public rubyInstallationUris = [
    vscode.Uri.joinPath(vscode.Uri.file(os.homedir()), ".rubies"),
    vscode.Uri.joinPath(vscode.Uri.file("/"), "opt", "rubies"),
  ];

  constructor(
    workspaceFolder: vscode.WorkspaceFolder,
    outputChannel: WorkspaceChannel,
    manuallySelectRuby: () => Promise<void>,
  ) {
    super(workspaceFolder, outputChannel, manuallySelectRuby);

    const configuredRubies = vscode.workspace
      .getConfiguration("rubyLsp")
      .get<string[] | undefined>("rubyVersionManager.chrubyRubies");

    if (configuredRubies) {
      this.rubyInstallationUris.push(
        ...configuredRubies.map((path) => vscode.Uri.file(path)),
      );
    }
  }

  async activate(): Promise<ActivationResult> {
    let versionInfo = await this.discoverRubyVersion();
    let rubyUri: vscode.Uri | undefined;

    // If the version informed is available, try to find the Ruby installation. Otherwise, try to fall back to an
    // existing version
    try {
      if (versionInfo) {
        rubyUri = await this.findRubyUri(versionInfo);
      } else {
        const fallback = await this.fallbackWithCancellation(
          "No .ruby-version file found. Trying to fall back to latest installed Ruby in 10 seconds",
          "You can create a .ruby-version file in a parent directory to configure a fallback",
          this.findFallbackRuby.bind(this),
          this.rubyVersionError.bind(this),
        );

        versionInfo = fallback.rubyVersion;
        rubyUri = fallback.uri;
      }
    } catch (error: any) {
      if (error instanceof RubyActivationCancellationError) {
        // Try to re-activate if the user has configured a fallback during cancellation
        return this.activate();
      }

      throw error;
    }

    // If we couldn't find a Ruby installation, that means there's a `.ruby-version` file, but that Ruby is not
    // installed. In this case, we fallback to a closest installation of Ruby - preferably only varying in patch
    try {
      if (!rubyUri) {
        const currentVersionInfo = { ...versionInfo };

        const fallback = await this.fallbackWithCancellation(
          `Couldn't find installation for ${versionInfo.version}. Trying to fall back to other Ruby in 10 seconds`,
          "You can cancel this fallback and install the required Ruby",
          async () => this.findClosestRubyInstallation(currentVersionInfo),
          () => this.missingRubyError(currentVersionInfo.version),
        );

        versionInfo = fallback.rubyVersion;
        rubyUri = fallback.uri;
      }
    } catch (error: any) {
      if (error instanceof RubyActivationCancellationError) {
        // Try to re-activate if the user has configured a fallback during cancellation
        return this.activate();
      }

      throw error;
    }

    this.outputChannel.info(
      `Discovered Ruby installation at ${rubyUri.fsPath}`,
    );

    const { defaultGems, gemHome, yjit, version } =
      await this.runActivationScript(rubyUri, versionInfo);

    this.outputChannel.info(
      `Activated Ruby environment: defaultGems=${defaultGems} gemHome=${gemHome} yjit=${yjit}`,
    );

    const rubyEnv = {
      GEM_HOME: gemHome,
      GEM_PATH: `${gemHome}${path.delimiter}${defaultGems}`,
      PATH: `${path.join(gemHome, "bin")}${path.delimiter}${path.join(
        defaultGems,
        "bin",
      )}${path.delimiter}${path.dirname(rubyUri.fsPath)}${path.delimiter}${this.getProcessPath()}`,
    };

    return {
      env: { ...process.env, ...rubyEnv },
      yjit,
      version,
      gemPath: [gemHome, defaultGems],
    };
  }

  protected getProcessPath() {
    return process.env.PATH;
  }

  // Returns the full URI to the Ruby executable
  protected async findRubyUri(
    rubyVersion: RubyVersion,
  ): Promise<vscode.Uri | undefined> {
    const possibleVersionNames = rubyVersion.engine
      ? [`${rubyVersion.engine}-${rubyVersion.version}`, rubyVersion.version]
      : [rubyVersion.version, `ruby-${rubyVersion.version}`];

    for (const uri of this.rubyInstallationUris) {
      let directories;

      try {
        directories = (await vscode.workspace.fs.readDirectory(uri)).sort(
          (left, right) => right[0].localeCompare(left[0]),
        );
      } catch (error: any) {
        // If the directory doesn't exist, keep searching
        this.outputChannel.debug(
          `Tried searching for Ruby installation in ${uri.fsPath} but it doesn't exist`,
        );
        continue;
      }

      for (const versionName of possibleVersionNames) {
        const targetDirectory = directories.find(([name]) =>
          name.startsWith(versionName),
        );

        if (targetDirectory) {
          return vscode.Uri.joinPath(uri, targetDirectory[0], "bin", "ruby");
        }
      }
    }

    return undefined;
  }

  // Run the activation script using the Ruby installation we found so that we can discover gem paths
  protected async runActivationScript(
    rubyExecutableUri: vscode.Uri,
    rubyVersion: RubyVersion,
  ): Promise<{
    defaultGems: string;
    gemHome: string;
    yjit: boolean;
    version: string;
  }> {
    // Typically, GEM_HOME points to $HOME/.gem/ruby/version_without_patch. For example, for Ruby 3.2.2, it would be
    // $HOME/.gem/ruby/3.2.0. However, chruby overrides GEM_HOME to use the patch part of the version, resulting in
    // $HOME/.gem/ruby/3.2.2. In our activation script, we check if a directory using the patch exists and then prefer
    // that over the default one.
    const script = [
      "user_dir = Gem.user_dir",
      "paths = Gem.path",
      "if paths.length > 2",
      "  paths.delete(Gem.default_dir)",
      "  paths.delete(Gem.user_dir)",
      "  if paths[0]",
      "    user_dir = paths[0] if Dir.exist?(paths[0])",
      "  end",
      "end",
      `newer_gem_home = File.join(File.dirname(user_dir), "${rubyVersion.version}")`,
      "gems = (Dir.exist?(newer_gem_home) ? newer_gem_home : user_dir)",
      `STDERR.print([Gem.default_dir, gems, !!defined?(RubyVM::YJIT), RUBY_VERSION].join("${ACTIVATION_SEPARATOR}"))`,
    ].join(";");

    const result = await this.runScript(
      `${rubyExecutableUri.fsPath} -W0 -e '${script}'`,
    );

    const [defaultGems, gemHome, yjit, version] =
      result.stderr.split(ACTIVATION_SEPARATOR);

    return { defaultGems, gemHome, yjit: yjit === "true", version };
  }

  private async findClosestRubyInstallation(rubyVersion: RubyVersion): Promise<{
    uri: vscode.Uri;
    rubyVersion: RubyVersion;
  }> {
    const [major, minor, _patch] = rubyVersion.version.split(".");
    const directories: { uri: vscode.Uri; rubyVersion: RubyVersion }[] = [];

    for (const uri of this.rubyInstallationUris) {
      try {
        // Accumulate all directories that match the `engine-version` pattern and that start with the same requested
        // major version. We do not try to approximate major versions
        (await vscode.workspace.fs.readDirectory(uri)).forEach(([name]) => {
          const match =
            /((?<engine>[A-Za-z]+)-)?(?<version>\d+\.\d+(\.\d+)?(-[A-Za-z0-9]+)?)/.exec(
              name,
            );

          if (match?.groups && match.groups.version.startsWith(major)) {
            directories.push({
              uri: vscode.Uri.joinPath(uri, name, "bin", "ruby"),
              rubyVersion: {
                engine: match.groups.engine,
                version: match.groups.version,
              },
            });
          }
        });
      } catch (error: any) {
        // If the directory doesn't exist, keep searching
        this.outputChannel.debug(
          `Tried searching for Ruby installation in ${uri.fsPath} but it doesn't exist`,
        );
        continue;
      }
    }

    // Sort the directories based on the difference between the minor version and the requested minor version. On
    // conflicts, we use the patch version to break the tie. If there's no distance, we prefer the higher patch version
    const closest = directories.sort((left, right) => {
      const leftVersion = left.rubyVersion.version.split(".");
      const rightVersion = right.rubyVersion.version.split(".");

      const leftDiff = Math.abs(Number(leftVersion[1]) - Number(minor));
      const rightDiff = Math.abs(Number(rightVersion[1]) - Number(minor));

      // If the distance to minor version is the same, prefer higher patch number
      if (leftDiff === rightDiff) {
        return Number(rightVersion[2] || 0) - Number(leftVersion[2] || 0);
      }

      return leftDiff - rightDiff;
    })[0];

    if (closest) {
      return closest;
    }

    throw new Error("Cannot find any Ruby installations");
  }

  // Returns the Ruby version information including version and engine. E.g.: ruby-3.3.0, truffleruby-21.3.0
  private async discoverRubyVersion(): Promise<RubyVersion | undefined> {
    let uri = this.bundleUri;
    const root = path.parse(uri.fsPath).root;
    let version: string;
    let rubyVersionUri: vscode.Uri;

    while (uri.fsPath !== root) {
      try {
        rubyVersionUri = vscode.Uri.joinPath(uri, ".ruby-version");
        const content = await vscode.workspace.fs.readFile(rubyVersionUri);
        version = content.toString().trim();
      } catch (error: any) {
        // If the file doesn't exist, continue going up the directory tree
        uri = vscode.Uri.file(path.dirname(uri.fsPath));
        continue;
      }

      if (version === "") {
        throw new Error(`Ruby version file ${rubyVersionUri} is empty`);
      }

      const match =
        /((?<engine>[A-Za-z]+)-)?(?<version>\d+\.\d+(\.\d+)?(-[A-Za-z0-9]+)?)/.exec(
          version,
        );

      if (!match?.groups) {
        throw new Error(
          `Ruby version file ${rubyVersionUri} contains invalid format. Expected (engine-)?version, got ${version}`,
        );
      }

      this.outputChannel.info(
        `Discovered Ruby version ${version} from ${rubyVersionUri.fsPath}`,
      );
      return { engine: match.groups.engine, version: match.groups.version };
    }

    return undefined;
  }

  private async fallbackWithCancellation<T>(
    title: string,
    message: string,
    fallbackFn: () => Promise<T>,
    errorFn: () => Error,
  ): Promise<T> {
    let gemfileContents;

    try {
      gemfileContents = await vscode.workspace.fs.readFile(
        vscode.Uri.joinPath(this.workspaceFolder.uri, "Gemfile"),
      );
    } catch (error: any) {
      // The Gemfile doesn't exist
    }

    // If the Gemfile includes ruby version restrictions, then trying to fall back may lead to errors
    if (
      gemfileContents &&
      /^ruby(\s|\()("|')[\d.]+/.test(gemfileContents.toString())
    ) {
      throw errorFn();
    }

    const fallback = await vscode.window.withProgress(
      {
        title,
        location: vscode.ProgressLocation.Notification,
        cancellable: true,
      },
      async (progress, token) => {
        progress.report({ message });

        // If they don't cancel, we wait 10 seconds before falling back so that they are aware of what's happening
        await new Promise<void>((resolve) => {
          setTimeout(resolve, 10000);

          // If the user cancels the fallback, resolve immediately so that they don't have to wait 10 seconds
          token.onCancellationRequested(() => {
            resolve();
          });
        });

        if (token.isCancellationRequested) {
          await this.handleCancelledFallback(errorFn);

          // We throw this error to be able to catch and re-run activation after the user has configured a fallback
          throw new RubyActivationCancellationError();
        }

        return fallbackFn();
      },
    );

    return fallback;
  }

  private async handleCancelledFallback(errorFn: () => Error) {
    const answer = await vscode.window.showInformationMessage(
      `The Ruby LSP requires a Ruby version to launch.
      You can define a fallback for the system or for the Ruby LSP only`,
      "System",
      "Ruby LSP only",
    );

    if (answer === "System") {
      await this.createParentRubyVersionFile(errorFn);
    } else if (answer === "Ruby LSP only") {
      await this.manuallySelectRuby();
    }

    throw errorFn();
  }

  private async createParentRubyVersionFile(errorFn: () => Error) {
    const items: vscode.QuickPickItem[] = [];

    for (const uri of this.rubyInstallationUris) {
      let directories;

      try {
        directories = (await vscode.workspace.fs.readDirectory(uri)).sort(
          (left, right) => right[0].localeCompare(left[0]),
        );

        directories.forEach((directory) => {
          items.push({
            label: directory[0],
          });
        });
      } catch (error: any) {
        continue;
      }
    }

    const answer = await vscode.window.showQuickPick(items, {
      title: "Select a Ruby version to use as fallback",
      ignoreFocusOut: true,
    });

    if (!answer) {
      throw errorFn();
    }

    const targetDirectory = await vscode.window.showOpenDialog({
      defaultUri: vscode.Uri.file(os.homedir()),
      openLabel: "Add fallback in this directory",
      canSelectFiles: false,
      canSelectFolders: true,
      canSelectMany: false,
      title: "Select the directory to create the .ruby-version fallback in",
    });

    if (!targetDirectory) {
      throw errorFn();
    }

    await vscode.workspace.fs.writeFile(
      vscode.Uri.joinPath(targetDirectory[0], ".ruby-version"),
      Buffer.from(answer.label),
    );
  }

  private async findFallbackRuby(): Promise<{
    uri: vscode.Uri;
    rubyVersion: RubyVersion;
  }> {
    for (const uri of this.rubyInstallationUris) {
      let directories;

      try {
        directories = (await vscode.workspace.fs.readDirectory(uri)).sort(
          (left, right) => right[0].localeCompare(left[0]),
        );

        let groups;
        let targetDirectory;

        for (const directory of directories) {
          const match =
            /((?<engine>[A-Za-z]+)-)?(?<version>\d+\.\d+(\.\d+)?(-[A-Za-z0-9]+)?)/.exec(
              directory[0],
            );

          if (match?.groups) {
            groups = match.groups;
            targetDirectory = directory;
            break;
          }
        }

        if (targetDirectory) {
          return {
            uri: vscode.Uri.joinPath(uri, targetDirectory[0], "bin", "ruby"),
            rubyVersion: {
              engine: groups!.engine,
              version: groups!.version,
            },
          };
        }
      } catch (error: any) {
        // If the directory doesn't exist, keep searching
        this.outputChannel.debug(
          `Tried searching for Ruby installation in ${uri.fsPath} but it doesn't exist`,
        );
        continue;
      }
    }

    throw new Error("Cannot find any Ruby installations");
  }

  private missingRubyError(version: string) {
    return new Error(`Cannot find Ruby installation for version ${version}`);
  }

  private rubyVersionError() {
    return new Error(
      `Cannot find .ruby-version file. Please specify the Ruby version in a
           .ruby-version either in ${this.bundleUri.fsPath} or in a parent directory`,
    );
  }
}
