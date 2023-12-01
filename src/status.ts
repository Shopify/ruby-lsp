import * as vscode from "vscode";
import { State } from "vscode-languageclient";

import { Command, STATUS_EMITTER, WorkspaceInterface } from "./common";

const STOPPED_SERVER_OPTIONS = [
  { label: "Ruby LSP: Start", description: Command.Start },
  { label: "Ruby LSP: Restart", description: Command.Restart },
];

const STARTED_SERVER_OPTIONS = [
  { label: "Ruby LSP: Stop", description: Command.Stop },
  { label: "Ruby LSP: Restart", description: Command.Restart },
];

export abstract class StatusItem {
  public item: vscode.LanguageStatusItem;

  constructor(id: string) {
    this.item = vscode.languages.createLanguageStatusItem(id, {
      scheme: "file",
      language: "ruby",
    });
  }

  abstract refresh(workspace: WorkspaceInterface): void;

  dispose(): void {
    this.item.dispose();
  }
}

export class RubyVersionStatus extends StatusItem {
  constructor() {
    super("rubyVersion");

    this.item.name = "Ruby LSP Status";
    this.item.command = {
      title: "Change Ruby version",
      command: Command.ChangeRubyVersion,
    };

    this.item.text = "Activating Ruby environment";
  }

  refresh(workspace: WorkspaceInterface): void {
    if (workspace.ruby.rubyVersion) {
      this.item.text = `Using Ruby ${workspace.ruby.rubyVersion}`;
    } else {
      this.item.text = "Ruby environment not activated";
    }
  }
}

export class ServerStatus extends StatusItem {
  constructor() {
    super("server");

    this.item.name = "Ruby LSP Status";
    this.item.text = "Ruby LSP: Starting";
    this.item.severity = vscode.LanguageStatusSeverity.Information;
    this.item.command = {
      title: "Configure",
      command: Command.ServerOptions,
      arguments: [STARTED_SERVER_OPTIONS],
    };
  }

  refresh(workspace: WorkspaceInterface): void {
    if (workspace.error) {
      this.item.text = "Ruby LSP: Error";
      this.item.command!.arguments = [STOPPED_SERVER_OPTIONS];
      this.item.severity = vscode.LanguageStatusSeverity.Error;
      return;
    }

    if (!workspace.lspClient) {
      return;
    }

    switch (workspace.lspClient.state) {
      case State.Running: {
        this.item.text = workspace.lspClient.serverVersion
          ? `Ruby LSP v${workspace.lspClient.serverVersion}: Running`
          : "Ruby LSP: Running";
        this.item.command!.arguments = [STARTED_SERVER_OPTIONS];
        this.item.severity = vscode.LanguageStatusSeverity.Information;
        break;
      }
      case State.Starting: {
        this.item.text = "Ruby LSP: Starting";
        this.item.command!.arguments = [STARTED_SERVER_OPTIONS];
        this.item.severity = vscode.LanguageStatusSeverity.Information;
        break;
      }
      case State.Stopped: {
        this.item.text = "Ruby LSP: Stopped";
        this.item.command!.arguments = [STOPPED_SERVER_OPTIONS];
        this.item.severity = vscode.LanguageStatusSeverity.Information;
        break;
      }
    }
  }
}

export class ExperimentalFeaturesStatus extends StatusItem {
  constructor() {
    super("experimentalFeatures");

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

  refresh(_workspace: WorkspaceInterface): void {}
}

export class YjitStatus extends StatusItem {
  constructor() {
    super("yjit");

    this.item.name = "YJIT";
    this.item.text = "Fetching YJIT information";
  }

  refresh(workspace: WorkspaceInterface): void {
    if (workspace.ruby.yjitEnabled) {
      this.item.text = "YJIT enabled";
    } else {
      this.item.text = "YJIT disabled";
    }
  }
}

export class FeaturesStatus extends StatusItem {
  constructor() {
    super("features");
    this.item.name = "Ruby LSP Features";
    this.item.command = {
      title: "Manage",
      command: Command.ToggleFeatures,
    };
    this.item.text = "Fetching feature information";
  }

  refresh(_workspace: WorkspaceInterface): void {
    const configuration = vscode.workspace.getConfiguration("rubyLsp");
    const features: Record<string, boolean> =
      configuration.get("enabledFeatures")!;
    const enabledFeatures = Object.keys(features).filter(
      (key) => features[key],
    );

    this.item.text = `${enabledFeatures.length}/${
      Object.keys(features).length
    } features enabled`;
  }
}

export class FormatterStatus extends StatusItem {
  constructor() {
    super("formatter");

    this.item.name = "Formatter";
    this.item.command = {
      title: "Help",
      command: Command.FormatterHelp,
    };
    this.item.text = "Fetching formatter information";
  }

  refresh(workspace: WorkspaceInterface): void {
    if (workspace.lspClient) {
      if (workspace.lspClient.formatter) {
        this.item.text = `Formatter: ${workspace.lspClient.formatter}`;
      } else {
        this.item.text =
          "Formatter: requires server to be v0.12.4 or higher to display this field";
      }
    }
  }
}

export class StatusItems {
  private readonly items: StatusItem[] = [];

  constructor() {
    this.items = [
      new RubyVersionStatus(),
      new ServerStatus(),
      new ExperimentalFeaturesStatus(),
      new YjitStatus(),
      new FeaturesStatus(),
      new FormatterStatus(),
    ];

    STATUS_EMITTER.event((workspace) => {
      if (workspace) {
        this.items.forEach((item) => item.refresh(workspace));
      }
    });
  }

  dispose() {
    this.items.forEach((item) => item.dispose());
  }
}
