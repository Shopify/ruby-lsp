/* eslint-disable no-process-env */
import { ExecOptions } from "child_process";
import path from "path";

import * as vscode from "vscode";
import { Executable } from "vscode-languageclient/node";

import {
  ComposeConfig,
  ContainerPathConverter,
  fetchPathMapping,
} from "../docker";

import { VersionManager, ActivationResult } from "./versionManager";

// Compose
//
// Docker Compose is a tool for defining and running multi-container Docker applications. If your project uses Docker
// Compose, you can run Ruby LSP in one of the services defined in your `docker-compose.yml` file. It also supports
// mutagen file synchronization and can be customized to use a different Docker Compose wrapper command.
export class Compose extends VersionManager {
  protected composeConfig: ComposeConfig = { services: {} } as ComposeConfig;

  async activate(): Promise<ActivationResult> {
    await this.ensureConfigured();

    const parsedResult = await this.runEnvActivationScript(
      `${this.composeRunCommand()} ${this.composeServiceName()} ruby`,
    );

    return {
      env: { ...process.env },
      yjit: parsedResult.yjit,
      version: parsedResult.version,
      gemPath: parsedResult.gemPath,
    };
  }

  runActivatedScript(command: string, options: ExecOptions = {}) {
    return this.runScript(
      `${this.composeRunCommand()} ${this.composeServiceName()} ${command}`,
      options,
    );
  }

  activateExecutable(executable: Executable) {
    const composeCommand = this.parseCommand(
      `${this.composeRunCommand()} ${this.composeServiceName()}`,
    );

    return {
      command: composeCommand.command,
      args: [
        ...composeCommand.args,
        executable.command,
        ...(executable.args || []),
      ],
      options: {
        ...executable.options,
        env: { ...(executable.options?.env || {}), ...composeCommand.env },
      },
    };
  }

  async buildPathConverter(workspaceFolder: vscode.WorkspaceFolder) {
    const pathMapping = fetchPathMapping(
      this.composeConfig,
      this.composeServiceName(),
    );

    const stats = Object.entries(pathMapping).map(([local, remote]) => {
      const absolute = path.resolve(workspaceFolder.uri.fsPath, local);
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
