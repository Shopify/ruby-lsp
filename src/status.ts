import * as vscode from "vscode";

import { Ruby, VersionManager } from "./ruby";

export enum ServerState {
  Starting = "Starting",
  Running = "Running",
  Stopped = "Stopped",
  Error = "Error",
}

// Lists every Command in the Ruby LSP
export enum Command {
  Start = "rubyLsp.start",
  Stop = "rubyLsp.stop",
  Restart = "rubyLsp.restart",
  ToggleExperimentalFeatures = "rubyLsp.toggleExperimentalFeatures",
  ServerOptions = "rubyLsp.serverOptions",
  ToggleYjit = "rubyLsp.toggleYjit",
  SelectVersionManager = "rubyLsp.selectRubyVersionManager",
}

const STOPPED_SERVER_OPTIONS = [
  { label: "Ruby LSP: Start", description: Command.Start },
  { label: "Ruby LSP: Restart", description: Command.Restart },
];

const STARTED_SERVER_OPTIONS = [
  { label: "Ruby LSP: Stop", description: Command.Stop },
  { label: "Ruby LSP: Restart", description: Command.Restart },
];

export interface ClientInterface {
  context: vscode.ExtensionContext;
  ruby: Ruby;
  state: ServerState;
}

export abstract class StatusItem {
  public item: vscode.LanguageStatusItem;
  protected context: vscode.ExtensionContext;
  protected client: ClientInterface;

  constructor(id: string, client: ClientInterface) {
    this.item = vscode.languages.createLanguageStatusItem(id, {
      scheme: "file",
      language: "ruby",
    });
    this.context = client.context;
    this.client = client;
    this.registerCommand();
  }

  abstract refresh(): void;
  abstract registerCommand(): void;

  dispose(): void {
    this.item.dispose();
  }
}

export class RubyVersionStatus extends StatusItem {
  constructor(client: ClientInterface) {
    super("rubyVersion", client);
    this.item.text = `Using Ruby ${client.ruby.rubyVersion}`;
    this.item.name = "Ruby LSP Status";
    this.item.command = {
      title: "Change version manager",
      command: Command.SelectVersionManager,
    };
  }

  refresh(): void {
    this.item.text = `Using Ruby ${this.client.ruby.rubyVersion}`;
  }

  registerCommand(): void {
    this.context.subscriptions.push(
      vscode.commands.registerCommand(
        Command.SelectVersionManager,
        async () => {
          const options = Object.values(VersionManager);
          const manager = await vscode.window.showQuickPick(options);

          if (manager !== undefined) {
            vscode.workspace
              .getConfiguration("rubyLsp")
              .update("rubyVersionManager", manager, true, true);
          }
        }
      )
    );
  }
}

export class ServerStatus extends StatusItem {
  constructor(client: ClientInterface) {
    super("server", client);
    this.item.name = "Ruby LSP Status";
    this.item.text = "Ruby LSP: Starting";
    this.item.severity = vscode.LanguageStatusSeverity.Information;
    this.item.command = {
      title: "Configure",
      command: Command.ServerOptions,
      arguments: [STARTED_SERVER_OPTIONS],
    };
  }

  refresh(): void {
    switch (this.client.state) {
      case ServerState.Running:
      case ServerState.Starting: {
        this.item.text = "Ruby LSP: Starting";
        this.item.command!.arguments = [STARTED_SERVER_OPTIONS];
        this.item.severity = vscode.LanguageStatusSeverity.Information;
        break;
      }
      case ServerState.Stopped: {
        this.item.text = "Ruby LSP: Stopped";
        this.item.command!.arguments = [STOPPED_SERVER_OPTIONS];
        this.item.severity = vscode.LanguageStatusSeverity.Information;
        break;
      }
      case ServerState.Error: {
        this.item.text = "Ruby LSP: Error";
        this.item.command!.arguments = [STOPPED_SERVER_OPTIONS];
        this.item.severity = vscode.LanguageStatusSeverity.Error;
        break;
      }
    }
  }

  registerCommand(): void {
    this.context.subscriptions.push(
      vscode.commands.registerCommand(
        Command.ServerOptions,
        async (options: [{ label: string; description: string }]) => {
          const result = await vscode.window.showQuickPick(options, {
            placeHolder: "Select server action",
          });

          if (result !== undefined)
            await vscode.commands.executeCommand(result.description);
        }
      )
    );
  }
}

export class ExperimentalFeaturesStatus extends StatusItem {
  constructor(client: ClientInterface) {
    super("experimentalFeatures", client);
    const experimentalFeaturesEnabled =
      vscode.workspace
        .getConfiguration("rubyLsp")
        .get("enableExperimentalFeatures") === true;
    const message = experimentalFeaturesEnabled
      ? "Experimental features enabled"
      : "Experimental features disabled";

    this.item.name = "Experimental features";
    this.item.text = message;
    this.item.command = {
      title: experimentalFeaturesEnabled ? "Disable" : "Enable",
      command: Command.ToggleExperimentalFeatures,
    };
  }

  refresh(): void {}

  registerCommand(): void {
    this.context.subscriptions.push(
      vscode.commands.registerCommand(
        Command.ToggleExperimentalFeatures,
        async () => {
          const lspConfig = vscode.workspace.getConfiguration("rubyLsp");
          const experimentalFeaturesEnabled = lspConfig.get(
            "enableExperimentalFeatures"
          );
          await lspConfig.update(
            "enableExperimentalFeatures",
            !experimentalFeaturesEnabled,
            true,
            true
          );
          const message = experimentalFeaturesEnabled
            ? "Experimental features disabled"
            : "Experimental features enabled";
          this.item.text = message;
          this.item.command!.title = experimentalFeaturesEnabled
            ? "Enable"
            : "Disable";
        }
      )
    );
  }
}

export class YjitStatus extends StatusItem {
  constructor(client: ClientInterface) {
    super("yjit", client);

    this.item.name = "YJIT";
    this.refresh();
  }

  refresh(): void {
    const useYjit: boolean | undefined = vscode.workspace
      .getConfiguration("rubyLsp")
      .get("yjit");

    if (useYjit && this.client.ruby.supportsYjit) {
      this.item.text = "YJIT enabled";

      this.item.command = {
        title: "Disable",
        command: Command.ToggleYjit,
      };
    } else {
      this.item.text = "YJIT disabled";

      if (this.client.ruby.supportsYjit) {
        this.item.command = {
          title: "Enable",
          command: Command.ToggleYjit,
        };
      }
    }
  }

  registerCommand(): void {
    this.context.subscriptions.push(
      vscode.commands.registerCommand(Command.ToggleYjit, () => {
        const lspConfig = vscode.workspace.getConfiguration("rubyLsp");
        const yjitEnabled = lspConfig.get("yjit");
        lspConfig.update("yjit", !yjitEnabled, true, true);
        this.item.text = yjitEnabled ? "YJIT disabled" : "YJIT enabled";
        this.item.command!.title = yjitEnabled ? "Enable" : "Disable";
      })
    );
  }
}

export class StatusItems {
  private items: StatusItem[] = [];

  constructor(client: ClientInterface) {
    this.items = [
      new RubyVersionStatus(client),
      new ServerStatus(client),
      new ExperimentalFeaturesStatus(client),
      new YjitStatus(client),
    ];
  }

  public refresh() {
    this.items.forEach((item) => item.refresh());
  }
}
