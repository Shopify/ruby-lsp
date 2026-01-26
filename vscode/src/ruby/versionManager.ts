import path from "path";

import * as vscode from "vscode";

import { WorkspaceChannel } from "../workspaceChannel";
import { asyncExec, isWindows } from "../common";

export interface ActivationResult {
  env: NodeJS.ProcessEnv;
  yjit: boolean;
  version: string;
  gemPath: string[];
}

// Detection result types for version managers
export type DetectionResult =
  | { type: "semantic"; marker: string } // Detected by semantic markers (e.g., "chruby", "rbenv")
  | { type: "path"; uri: vscode.Uri } // Detected with actual file/directory path
  | { type: "none" }; // No detection (not found or not applicable)

// Changes to either one of these values have to be synchronized with a corresponding update in `activation.rb`
export const ACTIVATION_SEPARATOR = "RUBY_LSP_ACTIVATION_SEPARATOR";

// Timeout for tool detection commands (in milliseconds)
const TOOL_DETECTION_TIMEOUT_MS = 1000;
export const VALUE_SEPARATOR = "RUBY_LSP_VS";
export const FIELD_SEPARATOR = "RUBY_LSP_FS";

export abstract class VersionManager {
  protected readonly outputChannel: WorkspaceChannel;
  protected readonly workspaceFolder: vscode.WorkspaceFolder;
  protected readonly bundleUri: vscode.Uri;
  protected readonly manuallySelectRuby: () => Promise<void>;
  protected readonly context: vscode.ExtensionContext;
  private readonly customBundleGemfile?: string;

  constructor(
    workspaceFolder: vscode.WorkspaceFolder,
    outputChannel: WorkspaceChannel,
    context: vscode.ExtensionContext,
    manuallySelectRuby: () => Promise<void>,
  ) {
    this.workspaceFolder = workspaceFolder;
    this.outputChannel = outputChannel;
    this.context = context;
    this.manuallySelectRuby = manuallySelectRuby;
    const customBundleGemfile: string = vscode.workspace.getConfiguration("rubyLsp").get("bundleGemfile")!;

    if (customBundleGemfile.length > 0) {
      this.customBundleGemfile = path.isAbsolute(customBundleGemfile)
        ? customBundleGemfile
        : path.resolve(path.join(this.workspaceFolder.uri.fsPath, customBundleGemfile));
    }

    this.bundleUri = this.customBundleGemfile
      ? vscode.Uri.file(path.dirname(this.customBundleGemfile))
      : workspaceFolder.uri;
  }

  /**
   * Activates the Ruby environment for this version manager.
   *
   * Implementations should discover the Ruby version, locate the Ruby installation,
   * and return all necessary environment variables and metadata to boot the Ruby LSP.
   *
   * @returns Activation result with environment variables, YJIT status, version, and gem paths
   * @throws Error if Ruby cannot be activated
   */
  abstract activate(): Promise<ActivationResult>;

  /**
   * Finds the first existing path from a list of possible paths.
   *
   * This helper iterates through paths in order and returns the first one
   * that exists in the filesystem, or undefined if none exist.
   *
   * @param paths - Array of URIs to check
   * @returns First existing URI or undefined if none exist
   */
  protected static async findFirst(paths: vscode.Uri[]): Promise<vscode.Uri | undefined> {
    for (const possiblePath of paths) {
      if (await this.pathExists(possiblePath)) {
        return possiblePath;
      }
    }

    return undefined;
  }

  /**
   * Checks if a path exists in the filesystem.
   *
   * @param uri - The URI to check for existence
   * @returns true if the path exists, false otherwise
   */
  protected static async pathExists(uri: vscode.Uri): Promise<boolean> {
    try {
      await vscode.workspace.fs.stat(uri);
      return true;
    } catch (_error: unknown) {
      return false;
    }
  }

  /**
   * Checks if a version manager tool exists by running its --version command.
   *
   * This method attempts to execute `tool --version` within the workspace
   * to verify the tool is available on the PATH. The command is run in an
   * interactive shell to ensure shell initialization files are sourced.
   *
   * @param tool - Name of the tool to check (e.g., "chruby", "rbenv")
   * @param workspaceFolder - Workspace folder to use as working directory
   * @param outputChannel - Channel for logging detection attempts
   * @returns true if the tool exists and responds to --version, false otherwise
   */
  static async toolExists(
    tool: string,
    workspaceFolder: vscode.WorkspaceFolder,
    outputChannel: WorkspaceChannel,
  ): Promise<boolean> {
    try {
      const shell = vscode.env.shell.replace(/(\s+)/g, "\\$1");
      const command = `${shell} -i -c '${tool} --version'`;

      outputChannel.info(`Checking if ${tool} is available on the path`);

      await asyncExec(command, {
        cwd: workspaceFolder.uri.fsPath,
        timeout: TOOL_DETECTION_TIMEOUT_MS,
      });
      return true;
    } catch {
      return false;
    }
  }

  /**
   * Runs the Ruby environment activation script to gather environment information.
   *
   * This executes the activation.rb script using the specified Ruby executable
   * to discover environment variables, gem paths, YJIT status, and version.
   * The activation script outputs data in a structured format separated by
   * ACTIVATION_SEPARATOR and FIELD_SEPARATOR constants.
   *
   * @param activatedRuby - Command to run Ruby (e.g., "ruby" or full path)
   * @returns Activation result with all environment information
   */
  protected async runEnvActivationScript(activatedRuby: string): Promise<ActivationResult> {
    const activationUri = vscode.Uri.joinPath(this.context.extensionUri, "activation.rb");

    const result = await this.runScript(`${activatedRuby} -EUTF-8:UTF-8 '${activationUri.fsPath}'`);

    const activationContent = new RegExp(`${ACTIVATION_SEPARATOR}([^]*)${ACTIVATION_SEPARATOR}`).exec(result.stderr);

    const [version, gemPath, yjit, ...envEntries] = activationContent![1].split(FIELD_SEPARATOR);

    return {
      version,
      gemPath: gemPath.split(","),
      yjit: yjit === "true",
      env: Object.fromEntries(envEntries.map((entry) => entry.split(VALUE_SEPARATOR))),
    };
  }

  /**
   * Runs a shell command in the bundle directory.
   *
   * This executes the given command using the user's preferred shell (from vscode.env.shell)
   * and inherits the current process environment. The shell is used to ensure version manager
   * initialization scripts are sourced. On Windows, no shell is specified to avoid PowerShell
   * quoting issues.
   *
   * @param command - Shell command to execute
   * @returns Promise resolving to command output
   */
  protected runScript(command: string) {
    let shell: string | undefined;

    // If the user has configured a default shell, we use that one since they are probably sourcing their version
    // manager scripts in that shell's configuration files. On Windows, we never set the shell no matter what to ensure
    // that activation runs on `cmd.exe` and not PowerShell, which avoids complex quoting and escaping issues.
    if (vscode.env.shell.length > 0 && !isWindows()) {
      shell = vscode.env.shell;
    }

    this.outputChannel.info(`Running command: \`${command}\` in ${this.bundleUri.fsPath} using shell: ${shell}`);

    return asyncExec(command, {
      cwd: this.bundleUri.fsPath,
      shell,
      env: process.env,
      encoding: "utf-8",
    });
  }

  /**
   * Searches for an executable within specified directories.
   *
   * This method checks each directory for the executable and returns the first
   * match found. If not found in any directory, returns the execName itself
   * which will attempt to find the executable in the PATH.
   *
   * @param directories - Array of directory URIs to search
   * @param execName - Name of the executable to find
   * @returns Full path to executable if found, otherwise the execName itself
   */
  protected async findExec(directories: vscode.Uri[], execName: string) {
    for (const uri of directories) {
      try {
        const fullUri = vscode.Uri.joinPath(uri, execName);
        await vscode.workspace.fs.stat(fullUri);
        this.outputChannel.info(`Found ${execName} executable at ${uri.fsPath}`);
        return fullUri.fsPath;
      } catch (_error: any) {
        // continue searching
      }
    }

    return execName;
  }

  /**
   * Constructs a URI for a Ruby executable within a Ruby installation directory.
   *
   * This helper builds the full path to the ruby executable by combining the
   * installation root with an optional version subdirectory and the bin/ruby path.
   *
   * Examples:
   * - rubyExecutableUri(/opt/rubies, "ruby-3.3.0") → /opt/rubies/ruby-3.3.0/bin/ruby
   * - rubyExecutableUri(/usr/local) → /usr/local/bin/ruby
   *
   * @param installationUri - The root directory of the Ruby installation
   * @param versionDirectory - Optional subdirectory name (e.g., "ruby-3.3.0")
   * @returns URI pointing to the Ruby executable
   */
  protected rubyExecutableUri(installationUri: vscode.Uri, versionDirectory?: string): vscode.Uri {
    const basePath = versionDirectory ? vscode.Uri.joinPath(installationUri, versionDirectory) : installationUri;
    return vscode.Uri.joinPath(basePath, "bin", "ruby");
  }
}
