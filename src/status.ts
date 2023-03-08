import * as vscode from "vscode";

import { Ruby, VersionManager } from "./ruby";

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

export class StatusItem {
  private context: vscode.ExtensionContext;
  private ruby: Ruby;
  private selector: vscode.DocumentSelector;
  private serverStatus: vscode.LanguageStatusItem;
  private yjitStatus: vscode.LanguageStatusItem;
  private rubyVersionStatus: vscode.LanguageStatusItem;
  private experimentalFeaturesStatus: vscode.LanguageStatusItem;

  constructor(context: vscode.ExtensionContext, ruby: Ruby) {
    this.context = context;
    this.ruby = ruby;
    this.selector = {
      scheme: "file",
      language: "ruby",
    };

    this.serverStatus = this.createStatusItem(
      "serverStatus",
      "Ruby LSP: Starting...",
      vscode.LanguageStatusSeverity.Information
    );

    this.serverStatus.command = {
      title: "Configure",
      command: Command.ServerOptions,
      arguments: [STARTED_SERVER_OPTIONS],
    };

    this.yjitStatus = vscode.languages.createLanguageStatusItem(
      "yjit",
      this.selector
    );

    this.refreshYjitStatus();
    this.rubyVersionStatus = this.createRubyStatus();
    this.experimentalFeaturesStatus = this.createExperimentalFeaturesStatus();
    this.registerCommands();
  }

  public refresh(status: Command, ruby: Ruby) {
    this.ruby = ruby;
    this.rubyVersionStatus.text = `Using Ruby ${this.ruby.rubyVersion}`;
    this.refreshYjitStatus();
    this.serverStatus.severity = vscode.LanguageStatusSeverity.Information;

    switch (status) {
      case Command.Start: {
        this.serverStatus.text = "Ruby LSP: Running...";
        this.serverStatus.command!.arguments = [STARTED_SERVER_OPTIONS];
        break;
      }
      case Command.Stop: {
        this.serverStatus.text = "Ruby LSP: Stopped";
        this.serverStatus.command!.arguments = [STOPPED_SERVER_OPTIONS];
        break;
      }
      case Command.Restart: {
        this.serverStatus.text = "Ruby LSP: Error";
        this.serverStatus.severity = vscode.LanguageStatusSeverity.Error;
        this.serverStatus.command!.arguments = [STOPPED_SERVER_OPTIONS];
      }
    }
  }

  private refreshYjitStatus() {
    this.yjitStatus.name = "Ruby LSP Status";
    const useYjit: boolean | undefined = vscode.workspace
      .getConfiguration("rubyLsp")
      .get("yjit");

    if (useYjit && this.ruby.supportsYjit) {
      this.yjitStatus.text = "YJIT enabled";

      this.yjitStatus.command = {
        title: "Disable",
        command: Command.ToggleYjit,
      };
    } else {
      this.yjitStatus.text = "YJIT disabled";

      if (this.ruby.supportsYjit) {
        this.yjitStatus.command = {
          title: "Enable",
          command: Command.ToggleYjit,
        };
      }
    }
  }

  private createRubyStatus() {
    const rubyVersion: vscode.LanguageStatusItem =
      vscode.languages.createLanguageStatusItem("rubyVersion", this.selector);
    rubyVersion.name = "Ruby LSP Status";
    rubyVersion.text = `Using Ruby ${this.ruby.rubyVersion}`;
    rubyVersion.command = {
      title: "Change version manager",
      command: Command.SelectVersionManager,
    };

    return rubyVersion;
  }

  private createStatusItem(
    id: string,
    text: string,
    severity: vscode.LanguageStatusSeverity
  ): vscode.LanguageStatusItem {
    const status: vscode.LanguageStatusItem =
      vscode.languages.createLanguageStatusItem(id, this.selector);
    status.name = "Ruby LSP Status";
    status.text = text;
    status.severity = severity;
    return status;
  }

  private createExperimentalFeaturesStatus() {
    const experimentalFeaturesEnabled =
      vscode.workspace
        .getConfiguration("rubyLsp")
        .get("enableExperimentalFeatures") === true;
    const message = experimentalFeaturesEnabled
      ? "Experimental features enabled"
      : "Experimental features disabled";

    const status: vscode.LanguageStatusItem =
      vscode.languages.createLanguageStatusItem(
        "experimentalFeatures",
        this.selector
      );

    status.text = message;
    status.command = {
      title: experimentalFeaturesEnabled ? "Disable" : "Enable",
      command: Command.ToggleExperimentalFeatures,
    };

    return status;
  }

  private registerCommands() {
    this.context.subscriptions.push(
      vscode.commands.registerCommand(Command.ToggleYjit, () => {
        const lspConfig = vscode.workspace.getConfiguration("rubyLsp");
        const yjitEnabled = lspConfig.get("yjit");
        lspConfig.update("yjit", !yjitEnabled, true, true);
        this.yjitStatus.text = yjitEnabled ? "YJIT disabled" : "YJIT enabled";
        this.yjitStatus.command!.title = yjitEnabled ? "Enable" : "Disable";
      })
    );

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
          this.experimentalFeaturesStatus.text = message;
          this.experimentalFeaturesStatus.command!.title =
            experimentalFeaturesEnabled ? "Enable" : "Disable";
        }
      )
    );

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
