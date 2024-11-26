/* eslint-disable no-process-env */
import path from "path";
import os from "os";
import { ExecOptions } from "child_process";

import * as vscode from "vscode";
import { Executable } from "vscode-languageclient/node";

import { WorkspaceChannel } from "../workspaceChannel";
import { asyncExec, PathConverterInterface, spawn } from "../common";

export interface ActivationResult {
  env: NodeJS.ProcessEnv;
  yjit: boolean;
  version: string;
  gemPath: string[];
}

export const ACTIVATION_SEPARATOR = "RUBY_LSP_ACTIVATION_SEPARATOR";

export class PathConverter implements PathConverterInterface {
  readonly pathMapping: [string, string][] = [];

  toRemotePath(path: string) {
    return path;
  }

  toLocalPath(path: string) {
    return path;
  }

  toRemoteUri(localUri: vscode.Uri) {
    return localUri;
  }
}

export abstract class VersionManager {
  public activationScript = [
    `STDERR.print("${ACTIVATION_SEPARATOR}" + `,
    "{ env: ENV.to_h, yjit: !!defined?(RubyVM::YJIT), version: RUBY_VERSION, gemPath: Gem.path }.to_json + ",
    `"${ACTIVATION_SEPARATOR}")`,
  ].join("");

  protected readonly outputChannel: WorkspaceChannel;
  protected readonly workspaceFolder: vscode.WorkspaceFolder;
  protected readonly bundleUri: vscode.Uri;
  protected readonly manuallySelectRuby: () => Promise<void>;

  private readonly customBundleGemfile?: string;

  constructor(
    workspaceFolder: vscode.WorkspaceFolder,
    outputChannel: WorkspaceChannel,
    manuallySelectRuby: () => Promise<void>,
  ) {
    this.workspaceFolder = workspaceFolder;
    this.outputChannel = outputChannel;
    this.manuallySelectRuby = manuallySelectRuby;
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

    this.bundleUri = this.customBundleGemfile
      ? vscode.Uri.file(path.dirname(this.customBundleGemfile))
      : workspaceFolder.uri;
  }

  // Activate the Ruby environment for the version manager, returning all of the necessary information to boot the
  // language server
  abstract activate(): Promise<ActivationResult>;

  runActivatedScript(command: string, options: ExecOptions = {}) {
    return this.runScript(command, options);
  }

  activateExecutable(executable: Executable) {
    return executable;
  }

  async buildPathConverter(_workspaceFolder: vscode.WorkspaceFolder) {
    return new PathConverter();
  }

  protected async runEnvActivationScript(activatedRuby: string) {
    const result = await this.runRubyCode(
      `${activatedRuby} -W0 -rjson`,
      this.activationScript,
    );

    this.outputChannel.debug(
      `Activation script output: ${JSON.stringify(result, null, 2)}`,
    );

    const activationContent = new RegExp(
      `${ACTIVATION_SEPARATOR}(.*)${ACTIVATION_SEPARATOR}`,
    ).exec(result.stderr);

    return this.parseWithErrorHandling(activationContent![1]);
  }

  protected parseWithErrorHandling(json: string) {
    try {
      return JSON.parse(json);
    } catch (error: any) {
      this.outputChannel.error(
        `Tried parsing invalid JSON environment: ${json}`,
      );

      throw error;
    }
  }

  // Runs the given command in the directory for the Bundle, using the user's preferred shell and inheriting the current
  // process environment
  protected runScript(command: string, options: ExecOptions = {}) {
    const execOptions = this.execOptions(options);

    this.outputChannel.info(
      `Running command: \`${command}\` in ${execOptions.cwd} using shell: ${execOptions.shell}`,
    );
    this.outputChannel.debug(
      `Environment used for command: ${JSON.stringify(execOptions.env)}`,
    );

    return asyncExec(command, execOptions);
  }

  protected runRubyCode(
    rubyCommand: string,
    code: string,
  ): Promise<{ stdout: string; stderr: string }> {
    return new Promise((resolve, reject) => {
      this.outputChannel.info(
        `Ruby \`${rubyCommand}\` running Ruby code: \`${code}\``,
      );

      const { command, args, env } = this.parseCommand(rubyCommand);
      const ruby = spawn(command, args, this.execOptions({ env }));

      let stdout = "";
      let stderr = "";

      ruby.stdout.on("data", (data) => {
        this.outputChannel.debug(`stdout: '${data.toString()}'`);
        if (data.toString().includes("END_OF_RUBY_CODE_OUTPUT")) {
          stdout += data.toString().replace(/END_OF_RUBY_CODE_OUTPUT.*/s, "");
          resolve({ stdout, stderr });
        } else {
          stdout += data.toString();
        }
      });
      ruby.stderr.on("data", (data) => {
        this.outputChannel.debug(`stderr: '${data.toString()}'`);
        stderr += data.toString();
      });
      ruby.on("error", (error) => {
        reject(error);
      });
      ruby.on("close", (status) => {
        if (status) {
          reject(new Error(`Process exited with status ${status}: ${stderr}`));
        } else {
          resolve({ stdout, stderr });
        }
      });

      const script = [
        "begin",
        ...code.split("\n").map((line) => `  ${line}`),
        "ensure",
        '  puts "END_OF_RUBY_CODE_OUTPUT"',
        "end",
      ].join("\n");

      ruby.stdin.write(script);
      ruby.stdin.end();
    });
  }

  protected execOptions(options: ExecOptions = {}): ExecOptions {
    let shell: string | undefined;

    // If the user has configured a default shell, we use that one since they are probably sourcing their version
    // manager scripts in that shell's configuration files. On Windows, we never set the shell no matter what to ensure
    // that activation runs on `cmd.exe` and not PowerShell, which avoids complex quoting and escaping issues.
    if (vscode.env.shell.length > 0 && os.platform() !== "win32") {
      shell = vscode.env.shell;
    }

    return {
      cwd: this.bundleUri.fsPath,
      shell,
      ...options,
      env: { ...process.env, ...options.env },
    };
  }

  // Parses a command string into its command, arguments, and environment variables
  protected parseCommand(commandString: string): {
    command: string;
    args: string[];
    env: Record<string, string>;
  } {
    // Regular expression to split arguments while respecting quotes
    const regex = /(?:[^\s"']+|"[^"]*"|'[^']*')+/g;

    const parts =
      commandString.match(regex)?.map((arg) => {
        // Remove surrounding quotes, if any
        return arg.replace(/^['"]|['"]$/g, "");
      }) ?? [];

    // Extract environment variables
    const env: Record<string, string> = {};
    while (parts[0] && parts[0].includes("=")) {
      const [key, value] = parts.shift()?.split("=") ?? [];
      if (key) {
        env[key] = value || "";
      }
    }

    // The first part is the command, the rest are arguments
    const command = parts.shift() || "";
    const args = parts;

    return { command, args, env };
  }

  // Tries to find `execName` within the given directories. Prefers the executables found in the given directories over
  // finding the executable in the PATH
  protected async findExec(directories: vscode.Uri[], execName: string) {
    for (const uri of directories) {
      try {
        const fullUri = vscode.Uri.joinPath(uri, execName);
        await vscode.workspace.fs.stat(fullUri);
        this.outputChannel.info(
          `Found ${execName} executable at ${uri.fsPath}`,
        );
        return fullUri.fsPath;
      } catch (error: any) {
        // continue searching
      }
    }

    return execName;
  }
}
