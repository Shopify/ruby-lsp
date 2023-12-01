/* eslint-disable no-process-env */
import path from "path";
import fs from "fs/promises";
import os from "os";

import * as vscode from "vscode";

import { RubyInterface, asyncExec, pathExists } from "./common";
import { WorkspaceChannel } from "./workspaceChannel";

interface ActivationEnvironment {
  defaultGems: string;
  gems: string;
  version: string;
  yjit: string;
}

// Where to search for Ruby installations. We need to cover all common cases for Ruby version managers, but we allow
// users to manually point to a Ruby installation if not covered here.
const RUBY_LOOKUP_PATHS =
  os.platform() === "win32"
    ? ["C:"]
    : [
        path.join("/", "opt", "rubies"),
        path.join(os.homedir(), ".rubies"),
        path.join(os.homedir(), ".rbenv", "versions"),
        path.join(os.homedir(), ".local", "share", "rtx", "installs", "ruby"),
        path.join(os.homedir(), ".asdf", "installs", "ruby"),
        path.join(os.homedir(), ".rvm", "rubies"),
      ];

export class Ruby implements RubyInterface {
  private readonly customBundleGemfile?: string;
  private readonly cwd: string;
  private readonly context: vscode.ExtensionContext;
  private readonly workspaceName: string;
  private readonly outputChannel: WorkspaceChannel;

  #env: NodeJS.ProcessEnv = process.env;
  #rubyVersion?: string;
  #yjitEnabled?: boolean;

  constructor(
    workingFolder: vscode.WorkspaceFolder,
    context: vscode.ExtensionContext,
    outputChannel: WorkspaceChannel,
  ) {
    // We allow users to define a custom Gemfile to run the LSP with. This is useful for projects using EOL rubies or
    // users that like to share their development dependencies across multiple projects in a separate Gemfile
    const customBundleGemfile: string = vscode.workspace
      .getConfiguration("rubyLsp")
      .get("bundleGemfile")!;

    if (customBundleGemfile.length > 0) {
      this.customBundleGemfile = path.isAbsolute(customBundleGemfile)
        ? customBundleGemfile
        : path.resolve(
            path.join(workingFolder.uri.fsPath, customBundleGemfile),
          );

      this.cwd = path.dirname(this.customBundleGemfile);
    } else {
      this.cwd = workingFolder.uri.fsPath;
    }

    this.outputChannel = outputChannel;
    this.context = context;
    this.workspaceName = workingFolder.name;
  }

  get env() {
    return this.#env;
  }

  get rubyVersion() {
    return this.#rubyVersion;
  }

  get yjitEnabled() {
    return this.#yjitEnabled;
  }

  async activate(rubyPath?: string) {
    let matchedRubyPath = rubyPath;
    if (!matchedRubyPath) {
      matchedRubyPath = await this.findRubyPath();
    }

    if (!(await pathExists(matchedRubyPath, fs.constants.X_OK))) {
      throw new Error(
        `Discovered Ruby path ${matchedRubyPath}, but VS Code does not have permissions to execute it`,
      );
    }

    const { defaultGems, gems, version, yjit } = await this.runActivationScript(
      matchedRubyPath!,
    );

    let userGemsPath = gems;
    const gemsetPath = path.join(this.cwd, ".ruby-gemset");

    if (await pathExists(gemsetPath)) {
      const gemset = (await fs.readFile(gemsetPath, "utf8")).trim();

      if (gemset) {
        userGemsPath = `${gems}@${gemset}`;
      }
    }

    const [major, minor, _patch] = version.split(".").map(Number);

    if (major < 3) {
      throw new Error(
        `The Ruby LSP requires Ruby 3.0 or newer to run. This project is using ${version}. \
        [See alternatives](https://github.com/Shopify/vscode-ruby-lsp?tab=readme-ov-file#ruby-version-requirement)`,
      );
    }

    this.outputChannel.info(
      `Activated Ruby environment: gem_home=${userGemsPath}, version=${version}, yjit=${yjit}, gem_root=${defaultGems}`,
    );

    const rubyEnv = {
      GEM_HOME: userGemsPath,
      GEM_PATH: `${userGemsPath}${path.delimiter}${defaultGems}`,
      PATH: `${path.join(userGemsPath, "bin")}${path.delimiter}${path.join(
        defaultGems,
        "bin",
      )}${path.delimiter}${matchedRubyPath}${path.delimiter}${process.env.PATH}`,
    };

    this.#env = {
      ...this.#env,
      ...rubyEnv,
    };
    this.#rubyVersion = version;

    // YJIT is enabled if Ruby was compiled with support for it and the Ruby version is equal or greater to 3.2
    this.#yjitEnabled = yjit === "constant" && major >= 3 && minor >= 2;

    // If the version is exactly 3.2, we enable YJIT through RUBYOPT. Starting with Ruby 3.3 the server enables YJIT
    if (this.yjitEnabled && major === 3 && minor === 2) {
      // RUBYOPT may be empty or it may contain bundler paths. In the second case, we must concat to avoid accidentally
      // removing the paths from the env variable
      if (this.#env.RUBYOPT) {
        this.#env.RUBYOPT.concat(" --yjit");
      } else {
        this.#env.RUBYOPT = "--yjit";
      }
    }

    this.deleteGcEnvironmentVariables();
    await this.setupBundlePath();

    // We need to set the entire NodeJS environment to match what we activated. This is only necessary to make the
    // Sorbet extension work
    process.env = this.#env;
    return rubyEnv;
  }

  // Manually select a Ruby version. Used for the language status item
  async changeVersion() {
    const rubyPath = await this.selectRubyInstallation();

    if (!rubyPath) {
      return;
    }

    await this.activate(rubyPath);
  }

  // Searches for a given filename in the current directory and all parent directories until it finds it or hits the
  // root
  private async searchAndReadFile(
    filename: string,
    searchParentDirectories: boolean,
  ) {
    let dir = this.cwd;

    if (!searchParentDirectories) {
      const fullPath = path.join(dir, filename);

      if (await pathExists(fullPath)) {
        return fs.readFile(fullPath, "utf8");
      }

      return;
    }

    while (await pathExists(dir)) {
      const versionFile = path.join(dir, filename);

      if (await pathExists(versionFile)) {
        return fs.readFile(versionFile, "utf8");
      }

      const parent = path.dirname(dir);

      // When we hit the root path (e.g. /), parent will be the same as dir.
      // We don't want to loop forever in this case, so we break out of the loop.
      if (parent === dir) {
        break;
      }

      dir = parent;
    }

    return undefined;
  }

  // Tries to read the configured Ruby version from a variety of different files, such as `.ruby-version`,
  // `.tool-versions` or `.rtx.toml`
  private async readConfiguredRubyVersion(): Promise<{
    engine?: string;
    version: string;
  }> {
    // Try to find a Ruby version in `dev.yml`. We search parent directories until we find it or hit the root
    let contents = await this.searchAndReadFile("dev.yml", false);
    if (contents) {
      const match = /- ruby: ('|")?(\d\.\d\.\d)/.exec(contents);
      const version = match && match[2];

      if (version) {
        return { version };
      }
    }

    // Try to find a Ruby version in `.ruby-version`. We search parent directories until we find it or hit the root
    contents = await this.searchAndReadFile(".ruby-version", true);

    // rbenv allows setting a global Ruby version in `~/.rbenv/version`. If we couldn't find a project specific
    // `.ruby-version` file, then we need to check for the global one
    const globalRbenvVersionPath = path.join(os.homedir(), ".rbenv", "version");
    if (!contents && (await pathExists(globalRbenvVersionPath))) {
      contents = await fs.readFile(globalRbenvVersionPath, "utf8");
    }

    if (contents) {
      const match =
        /((?<engine>[A-Za-z]+)-)?(?<version>\d\.\d\.\d(-[A-Za-z0-9]+)?)/.exec(
          contents,
        );

      if (match && match.groups) {
        return { engine: match.groups.engine, version: match.groups.version };
      }
    }

    // Try to find a Ruby version in `.tool-versions`. We search parent directories until we find it or hit the root
    contents = await this.searchAndReadFile(".tool-versions", true);
    if (contents) {
      const match = /ruby (\d\.\d\.\d(-[A-Za-z0-9]+)?)/.exec(contents);
      const version = match && match[1];

      if (version) {
        return { version };
      }
    }

    // Try to find a Ruby version in `.rtx.toml`. Note: rtx has been renamed to mise, which is handled below. We will
    // support rtx for a while until people finish migrating their configurations
    contents = await this.searchAndReadFile(".rtx.toml", false);
    if (contents) {
      const match = /ruby\s+=\s+("|')(.*)("|')/.exec(contents);
      const version = match && match[2];

      if (version) {
        return { version };
      }
    }

    // Try to find a Ruby version in `.mise.toml`
    contents = await this.searchAndReadFile(".mise.toml", false);
    if (contents) {
      const match = /ruby\s+=\s+("|')(.*)("|')/.exec(contents);
      const version = match && match[2];

      if (version) {
        return { version };
      }
    }

    throw new Error(
      "Could not find a valid Ruby version in any of `.ruby-version`, `.tool-versions`, `.rtx.toml` " +
        "or `.mise.toml` files",
    );
  }

  // Searches all `rubyLookupPaths` to find an installation that matches `version`
  private async findRubyDir(version: string, engine: string | undefined) {
    // Fast path: if the version contains major, minor and patch, we can just search for a directory directly using that
    // as the name and return it
    if (/\d\.\d\.\d/.exec(version)) {
      for (const dir of RUBY_LOOKUP_PATHS) {
        let fullPath = path.join(dir, version);

        if (await pathExists(fullPath, fs.constants.F_OK)) {
          return fullPath;
        }

        // Some version managers will define versions with `engine-version`, e.g.: `ruby-3.1.2`. We need to check if a
        // directory exists for that format if the engine is set
        if (engine) {
          fullPath = path.join(dir, `${engine}-${version}`);

          if (await pathExists(fullPath, fs.constants.F_OK)) {
            return fullPath;
          }
        }

        // RubyInstaller for Windows places rubies in paths like `C:\Ruby32-x64`
        if (os.platform() === "win32") {
          const [major, minor, _patch] = version.split(".").map(Number);
          fullPath = path.join(dir, `Ruby${major}${minor}-${os.arch()}`);

          if (await pathExists(fullPath, fs.constants.F_OK)) {
            return fullPath;
          }
        }
      }

      throw new Error(
        `Cannot find installation directory for Ruby version ${version}`,
      );
    }

    // Slow path: some version managers allow configuring the Ruby version without specifying the patch (e.g.: `ruby
    // 3.1`). In these cases, we have to discover all available directories and match whatever the latest patch
    // installed is
    for (const dir of RUBY_LOOKUP_PATHS) {
      // Find all existings directories. This will return an array with directories like:
      // - /opt/rubies/3.0.0
      // - /opt/rubies/3.1.2
      // - /opt/rubies/3.2.2
      const existingDirectories = (
        await fs.readdir(dir, { withFileTypes: true })
      ).filter((entry) => entry.isDirectory());

      // Sort directories by name so that the latest version is the first one
      existingDirectories.sort((first, second) =>
        second.name.localeCompare(first.name),
      );

      // Find the first directory that starts with the requested version
      const match = existingDirectories.find((dir) => {
        const name = dir.name;
        return (
          name.startsWith(version) ||
          (engine && name.startsWith(`${engine}-${version}`))
        );
      });

      if (match) {
        return `${dir}/${match.name}`;
      }
    }

    throw new Error(
      `Cannot find installation directory for Ruby version ${version}`,
    );
  }

  // Remove garbage collection customizations from the environment. Normally, people set these for Rails apps, but those
  // customizations can often degrade the LSP performance
  private deleteGcEnvironmentVariables() {
    Object.keys(this.#env).forEach((key) => {
      if (key.startsWith("RUBY_GC")) {
        delete this.#env[key];
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

    this.#env.BUNDLE_GEMFILE = this.customBundleGemfile;
  }

  // Show an error message because we couldn't detect Ruby automatically and give the opportunity for users to manually
  // select an installation
  private async showRubyFallbackDialog(errorMessage: string): Promise<string> {
    const answer = await vscode.window.showErrorMessage(
      `Automatic Ruby detection failed: ${errorMessage}.
      Please address the issue and reload or manually select your Ruby install`,
      "Select Ruby",
      "Reload window",
    );

    if (!answer) {
      throw new Error("Ruby LSP requires a Ruby installation to run");
    }

    if (answer === "Select Ruby") {
      return this.selectRubyInstallation();
    }

    return vscode.commands.executeCommand("workbench.action.reloadWindow");
  }

  // Show a file selection dialog for picking the Ruby binary
  private async selectRubyInstallation(): Promise<string> {
    const answer = await vscode.window.showInformationMessage(
      "Update global or workspace Ruby path?",
      "global",
      "workspace",
      "clear previous workspace selection",
    );

    if (!answer) {
      throw new Error("Ruby LSP requires a Ruby installation to run");
    }

    if (answer === "clear previous workspace selection") {
      this.context.workspaceState.update(
        `rubyLsp.selectedRubyPath.${this.workspaceName}`,
        undefined,
      );

      return this.findRubyPath();
    }

    const selection = await vscode.window.showOpenDialog({
      title: `Select Ruby binary path for ${answer} configuration`,
      openLabel: "Select Ruby binary",
    });

    if (!selection) {
      throw new Error("Ruby LSP requires a Ruby installation to run");
    }

    const rubyPath = selection[0].fsPath;

    if (answer === "global") {
      vscode.workspace
        .getConfiguration("rubyLsp")
        .update("rubyExecutablePath", rubyPath, true, true);
    } else {
      // We must update the cached Ruby path for this workspace if the user decided to change it
      this.context.workspaceState.update(
        `rubyLsp.selectedRubyPath.${this.workspaceName}`,
        path.dirname(rubyPath),
      );
    }

    return rubyPath;
  }

  // Returns the bin directory for the Ruby installation
  private async findRubyPath(): Promise<string> {
    let rubyPath: string;

    // Try to identify the Ruby version and the Ruby installation path automatically. If we fail to find it, we
    // display an error message with the reason and allow the user to manually select a Ruby installation path
    try {
      const { engine, version } = await this.readConfiguredRubyVersion();
      this.outputChannel.info(`Discovered Ruby version ${version}`);

      const selectedCachedPath: string | undefined =
        this.context.workspaceState.get(
          `rubyLsp.selectedRubyPath.${this.workspaceName}`,
        );

      // If the user selected a Ruby path manually, then we need to respect that selection
      if (selectedCachedPath) {
        this.outputChannel.info(
          `Using cached Ruby path: ${selectedCachedPath}`,
        );
        return selectedCachedPath;
      }

      const cachedPath: string | undefined = this.context.workspaceState.get(
        `rubyLsp.rubyPath.${this.workspaceName}`,
      );

      // If we already cached the Ruby installation path for this workspace and the Ruby version hasn't changed, just
      // return the cached path. Otherwise, we will re-discover the path and cache it at the end of this method
      if (cachedPath && path.basename(path.dirname(cachedPath)) === version) {
        this.outputChannel.info(`Using cached Ruby path: ${cachedPath}`);
        return cachedPath;
      }

      rubyPath = path.join(await this.findRubyDir(version, engine), "bin");
      this.outputChannel.info(`Found Ruby installation in ${rubyPath}`);
    } catch (error: any) {
      // If there's a globally configured Ruby path, then use it
      const globalRubyPath: string | undefined = vscode.workspace
        .getConfiguration("rubyLsp")
        .get("rubyExecutablePath");

      if (globalRubyPath) {
        const binDir = path.dirname(globalRubyPath);
        this.outputChannel.info(`Using configured global Ruby path: ${binDir}`);
        return binDir;
      }

      rubyPath = await this.showRubyFallbackDialog(error.message);

      // If we couldn't discover the Ruby path and the user didn't select one, we have no way to launch the server
      if (!rubyPath) {
        throw new Error("Ruby LSP requires a Ruby installation to run");
      }

      // We ask users to select the Ruby binary directly, but we actually need the bin directory containing it
      rubyPath = path.dirname(rubyPath);
      this.outputChannel.info(`Selected Ruby installation path: ${rubyPath}`);
    }

    // Cache the discovered Ruby path for this workspace
    this.context.workspaceState.update(
      `rubyLsp.rubyPath.${this.workspaceName}`,
      rubyPath,
    );
    return rubyPath;
  }

  // Run the activation script using the Ruby installation we found so that we can discover gem paths
  private async runActivationScript(
    rubyBinPath: string,
  ): Promise<ActivationEnvironment> {
    // Typically, GEM_HOME points to $HOME/.gem/ruby/version_without_patch. For example, for Ruby 3.2.2, it would be
    // $HOME/.gem/ruby/3.2.0. However, certain version managers override GEM_HOME to use the patch part of the version,
    // resulting in $HOME/.gem/ruby/3.2.2. In our activation script, we check if a directory using the patch exists and
    // then prefer that over the default one.
    //
    // Note: this script follows an odd code style to avoid the usage of && or ||, which lead to syntax errors in
    // certain shells if not properly escaped (Windows)
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
      "newer_gem_home = File.join(File.dirname(user_dir), RUBY_VERSION)",
      "gems = (Dir.exist?(newer_gem_home) ? newer_gem_home : user_dir)",
      "data = { defaultGems: Gem.default_dir, gems: gems, version: RUBY_VERSION, yjit: defined?(RubyVM::YJIT) }",
      "STDERR.print(JSON.dump(data))",
    ].join(";");

    const result = await asyncExec(
      `${path.join(rubyBinPath, "ruby")} -rjson -e '${script}'`,
      { cwd: this.cwd },
    );

    return JSON.parse(result.stderr);
  }
}
