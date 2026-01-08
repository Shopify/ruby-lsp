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

  // Activate the Ruby environment for the version manager, returning all of the necessary information to boot the
  // language server
  abstract activate(): Promise<ActivationResult>;

  // Finds the first existing path from a list of possible paths
  protected static async findFirst(paths: vscode.Uri[]): Promise<vscode.Uri | undefined> {
    for (const possiblePath of paths) {
      try {
        await vscode.workspace.fs.stat(possiblePath);
        return possiblePath;
      } catch (_error: any) {
        // Continue looking
      }
    }

    return undefined;
  }

  // Checks if a tool exists by running `tool --version`
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

  // Runs the given command in the directory for the Bundle, using the user's preferred shell and inheriting the current
  // process environment
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

  // Tries to find `execName` within the given directories. Prefers the executables found in the given directories over
  // finding the executable in the PATH
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
   * Constructs a URI for a Ruby executable within a Ruby installation directory
   * @param installationUri - The root directory of the Ruby installation
   * @param versionDirectory - Optional subdirectory name (e.g., "ruby-3.3.0")
   * @returns URI pointing to the Ruby executable (e.g., /path/to/ruby-3.3.0/bin/ruby)
   */
  protected rubyExecutableUri(installationUri: vscode.Uri, versionDirectory?: string): vscode.Uri {
    const basePath = versionDirectory ? vscode.Uri.joinPath(installationUri, versionDirectory) : installationUri;
    return vscode.Uri.joinPath(basePath, "bin", "ruby");
  }
}
