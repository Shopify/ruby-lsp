import * as vscode from "vscode";

import { Ruby, VersionManager } from "./ruby";

export enum ServerCommand {
  Start = "ruby-lsp.start",
  Stop = "ruby-lsp.stop",
  Restart = "ruby-lsp.restart",
}

const STOPPED_SERVER_OPTIONS = [
  { label: "Ruby LSP: Start", description: "ruby-lsp.start" },
  { label: "Ruby LSP: Restart", description: "ruby-lsp.restart" },
];

const STARTED_SERVER_OPTIONS = [
  { label: "Ruby LSP: Stop", description: "ruby-lsp.stop" },
  { label: "Ruby LSP: Restart", description: "ruby-lsp.restart" },
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
      command: "rubyLsp.serverOptions",
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

  public async refresh(status: ServerCommand, ruby: Ruby) {
    this.ruby = ruby;
    this.rubyVersionStatus.text = `Using Ruby ${this.ruby.rubyVersion}`;
    this.refreshYjitStatus();
    this.serverStatus.severity = vscode.LanguageStatusSeverity.Information;

    switch (status) {
      case ServerCommand.Start: {
        this.serverStatus.text = "Ruby LSP: Running...";
        this.serverStatus.command!.arguments = [STARTED_SERVER_OPTIONS];
        break;
      }
      case ServerCommand.Stop: {
        this.serverStatus.text = "Ruby LSP: Stopped";
        this.serverStatus.command!.arguments = [STOPPED_SERVER_OPTIONS];
        break;
      }
      case ServerCommand.Restart: {
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
        command: "rubyLsp.toggleYjit",
      };
    } else {
      this.yjitStatus.text = "YJIT disabled";

      if (this.ruby.supportsYjit) {
        this.yjitStatus.command = {
          title: "Enable",
          command: "rubyLsp.toggleYjit",
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
      command: "rubyLsp.selectRubyVersionManager",
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
      command: "rubyLsp.toggleExperimentalFeatures",
    };

    return status;
  }

  private registerCommands() {
    this.context.subscriptions.push(
      vscode.commands.registerCommand("rubyLsp.toggleYjit", async () => {
        const lspConfig = vscode.workspace.getConfiguration("rubyLsp");
        const yjitEnabled = lspConfig.get("yjit");
        lspConfig.update("yjit", !yjitEnabled, true, true);
        this.yjitStatus.text = yjitEnabled ? "YJIT disabled" : "YJIT enabled";
        this.yjitStatus.command!.title = yjitEnabled ? "Enable" : "Disable";
      })
    );

    this.context.subscriptions.push(
      vscode.commands.registerCommand(
        "rubyLsp.serverOptions",
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
        "rubyLsp.toggleExperimentalFeatures",
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
        "rubyLsp.selectRubyVersionManager",
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
