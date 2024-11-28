/* eslint-disable no-process-env */
import path from "path";
import os from "os";
import { StringDecoder } from "string_decoder";
import { ExecOptions } from "child_process";

import * as vscode from "vscode";
import { Executable } from "vscode-languageclient/node";

import {
  ComposeConfig,
  ContainerPathConverter,
  fetchPathMapping,
} from "../docker";
import { parseCommand, spawn } from "../common";

import {
  VersionManager,
  ActivationResult,
  ACTIVATION_SEPARATOR,
} from "./versionManager";

// Compose
//
// Docker Compose is a tool for defining and running multi-container Docker applications. If your project uses Docker
// Compose, you can run Ruby LSP in one of the services defined in your `docker-compose.yml` file. It also supports
// mutagen file synchronization and can be customized to use a different Docker Compose wrapper command.
export class Compose extends VersionManager {
  protected composeConfig: ComposeConfig = { services: {} } as ComposeConfig;

  async activate(): Promise<ActivationResult> {
    await this.ensureConfigured();

    const rubyCommand = `${this.composeRunCommand()} ${this.composeServiceName()} ruby -W0 -rjson`;
    const { stderr: output } = await this.runRubyCode(
      rubyCommand,
      this.activationScript,
    );

    this.outputChannel.debug(`Activation output: ${output}`);

    const activationContent = new RegExp(
      `${ACTIVATION_SEPARATOR}(.*)${ACTIVATION_SEPARATOR}`,
    ).exec(output);

    const parsedResult = this.parseWithErrorHandling(activationContent![1]);
    const pathConverter = await this.buildPathConverter();

    const wrapCommand = (executable: Executable) => {
      const composeCommad = parseCommand(
        `${this.composeRunCommand()} ${this.composeServiceName()}`,
      );

      const command = {
        command: composeCommad.command,
        args: [
          ...(composeCommad.args ?? []),
          executable.command,
          ...(executable.args ?? []),
        ],
        options: {
          ...executable.options,
          env: {
            ...executable.options?.env,
            ...composeCommad.options?.env,
          },
        },
      };

      return command;
    };

    return {
      env: { ...process.env },
      yjit: parsedResult.yjit,
      version: parsedResult.version,
      gemPath: parsedResult.gemPath,
      pathConverter,
      wrapCommand,
    };
  }

  protected async buildPathConverter() {
    const pathMapping = fetchPathMapping(
      this.composeConfig,
      this.composeServiceName(),
    );

    const stats = Object.entries(pathMapping).map(([local, remote]) => {
      const absolute = path.resolve(this.workspaceFolder.uri.fsPath, local);
      return vscode.workspace.fs.stat(vscode.Uri.file(absolute)).then(
        (stat) => ({ stat, local, remote, absolute }),
        () => ({ stat: undefined, local, remote, absolute }),
      );
    });

    const filteredMapping = (await Promise.all(stats)).reduce(
      (acc, { stat, local, remote, absolute }) => {
        if (stat?.type === vscode.FileType.Directory) {
          this.outputChannel.info(`Path ${absolute} mapped to ${remote}`);
          acc[absolute] = remote;
        } else {
          this.outputChannel.debug(
            `Skipping path ${local} because it does not exist`,
          );
        }

        return acc;
      },
      {} as Record<string, string>,
    );

    return new ContainerPathConverter(filteredMapping, this.outputChannel);
  }

  protected composeRunCommand(): string {
    return `${this.composeCommand()} run --rm -i`;
  }

  protected composeServiceName(): string {
    const service: string | undefined = vscode.workspace
      .getConfiguration("rubyLsp.rubyVersionManager")
      .get("composeService");

    if (service === undefined) {
      throw new Error(
        "The composeService configuration must be set when 'compose' is selected as the version manager. \
        See the [README](https://shopify.github.io/ruby-lsp/version-managers.html) for instructions.",
      );
    }

    return service;
  }

  protected composeCommand(): string {
    const composeCustomCommand: string | undefined = vscode.workspace
      .getConfiguration("rubyLsp.rubyVersionManager")
      .get("composeCustomCommand");

    return (
      composeCustomCommand ||
      "docker --log-level=error compose --progress=quiet"
    );
  }

  protected async ensureConfigured() {
    this.composeConfig = await this.getComposeConfig();
    const services: vscode.QuickPickItem[] = [];

    const config = vscode.workspace.getConfiguration("rubyLsp");
    const currentService = config.get("rubyVersionManager.composeService") as
      | string
      | undefined;

    if (currentService && this.composeConfig.services[currentService]) {
      return;
    }

    for (const [name, _service] of Object.entries(
      this.composeConfig.services,
    )) {
      services.push({ label: name });
    }

    const answer = await vscode.window.showQuickPick(services, {
      title: "Select Docker Compose service where to run ruby-lsp",
      ignoreFocusOut: true,
    });

    if (!answer) {
      throw new Error("No compose service selected");
    }

    const managerConfig = config.inspect("rubyVersionManager");
    const workspaceConfig = managerConfig?.workspaceValue || {};

    await config.update("rubyVersionManager", {
      ...workspaceConfig,
      ...{ composeService: answer.label },
    });
  }

  protected runRubyCode(
    rubyCommand: string,
    code: string,
  ): Promise<{ stdout: string; stderr: string }> {
    return new Promise((resolve, reject) => {
      this.outputChannel.info(
        `Ruby \`${rubyCommand}\` running Ruby code: \`${code}\``,
      );

      const {
        command,
        args,
        options: { env } = { env: {} },
      } = parseCommand(rubyCommand);
      const ruby = spawn(command, args, this.execOptions({ env }));

      let stdout = "";
      let stderr = "";

      const stdoutDecoder = new StringDecoder("utf-8");
      const stderrDecoder = new StringDecoder("utf-8");

      ruby.stdout.on("data", (data) => {
        stdout += stdoutDecoder.write(data);

        if (stdout.includes("END_OF_RUBY_CODE_OUTPUT")) {
          stdout = stdout.replace(/END_OF_RUBY_CODE_OUTPUT.*/s, "");
          resolve({ stdout, stderr });
        }
      });
      ruby.stderr.on("data", (data) => {
        stderr += stderrDecoder.write(data);
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

      this.outputChannel.info(`Running Ruby code:\n${script}`);

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

  private async getComposeConfig(): Promise<ComposeConfig> {
    try {
      const { stdout, stderr: _stderr } = await this.runScript(
        `${this.composeCommand()} config --format=json`,
      );

      const config = JSON.parse(stdout) as ComposeConfig;

      return config;
    } catch (error: any) {
      throw new Error(
        `Failed to read docker-compose configuration: ${error.message}`,
      );
    }
  }
}
