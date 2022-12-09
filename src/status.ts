import * as vscode from "vscode";

import {
  isGemMissing,
  addGem,
  bundleCheck,
  bundleInstall,
  isGemOutdated,
  updateGem,
} from "./bundler";
import { Ruby } from "./ruby";

export const enum ServerCommand {
  Start = "ruby-lsp.start",
  Stop = "ruby-lsp.stop",
  Error = "ruby-lsp.restart",
}

export class StatusItem {
  private context: vscode.ExtensionContext;
  private ruby: Ruby;
  private selector: vscode.DocumentSelector;
  private serverStatus: vscode.LanguageStatusItem;

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
      vscode.LanguageStatusSeverity?.Warning
    );

    this.serverStatus.command = {
      title: "Restart server",
      command: ServerCommand.Error,
    };

    this.createYjitStatus(this.ruby);
    this.createRubyStatus(this.ruby);
  }

  public async updateStatus(status: ServerCommand) {
    if (this.serverStatus) {
      this.serverStatus.dispose();
    }

    switch (status) {
      case ServerCommand.Start: {
        this.serverStatus = this.createStatusItem(
          "serverStatus",
          "Ruby LSP: Running...",
          vscode.LanguageStatusSeverity?.Warning
        );

        this.serverStatus.command = {
          title: "Stop Server",
          command: ServerCommand.Stop,
        };

        this.activateGemOutdatedButton();

        break;
      }
      case ServerCommand.Stop: {
        this.serverStatus = this.createStatusItem(
          "serverStatus",
          "Ruby LSP: Stopped",
          vscode.LanguageStatusSeverity?.Warning
        );

        this.serverStatus.command = {
          title: "Start Server",
          command: ServerCommand.Start,
        };

        break;
      }
      case ServerCommand.Error: {
        this.serverStatus = this.createStatusItem(
          "serverStatus",
          "Ruby LSP: Error",
          vscode.LanguageStatusSeverity?.Error
        );

        this.serverStatus.command = {
          title: "Restart Server",
          command: ServerCommand.Error,
        };
      }
    }
  }

  public async installGems(): Promise<boolean> {
    if (await bundleCheck()) {
      this.updateStatus(ServerCommand.Error);
      const status: vscode.LanguageStatusItem = this.createStatusItem(
        "installGems",
        "Ruby LSP: The gems in the bundle are not installed.",
        vscode.LanguageStatusSeverity?.Error
      );

      this.context.subscriptions.push(
        vscode.commands.registerCommand("ruby-lsp.installGems", () => {
          status.text = "Ruby LSP: Installing gems...";
          status.command = undefined;
          status.busy = true;
          bundleInstall()
            .then(() => {
              status.dispose();
              this.addMissingGem();
            })
            .catch(() => {
              status.dispose();
              this.createStatusItem(
                "installFail",
                "Ruby LSP: Failed to install gems.",
                vscode.LanguageStatusSeverity?.Error
              );
            });
        })
      );

      status.command = {
        title: "Run bundle install",
        command: "ruby-lsp.installGems",
      };
      return true;
    }
    return false;
  }

  public async addMissingGem(): Promise<boolean> {
    if (await isGemMissing()) {
      this.updateStatus(ServerCommand.Error);
      const status: vscode.LanguageStatusItem = this.createStatusItem(
        "addMissingGem",
        "Ruby LSP: Bundle Add",
        vscode.LanguageStatusSeverity?.Error
      );

      this.context.subscriptions.push(
        vscode.commands.registerCommand("ruby-lsp.addMissingGem", () => {
          status.text = "Ruby LSP: Adding gem...";
          status.command = undefined;
          status.busy = true;
          addGem()
            .then(() => status.dispose())
            .catch(() => {});
        })
      );

      status.command = {
        title: "Run bundle add and install",
        command: "ruby-lsp.addMissingGem",
      };
      return true;
    }
    return false;
  }

  private async activateGemOutdatedButton() {
    const gemOutdated = await isGemOutdated();
    if (!gemOutdated) {
      return;
    }

    const commandId = "updateOutdatedGem";

    const status: vscode.LanguageStatusItem = this.createStatusItem(
      "updateGem",
      "Ruby LSP: The gem is not up-to-date",
      vscode.LanguageStatusSeverity?.Warning
    );

    this.context.subscriptions.push(
      vscode.commands.registerCommand(commandId, async () => {
        status.text = "Ruby LSP: Updating Ruby LSP";
        status.busy = true;
        status.command = undefined;

        const result = await updateGem();

        if (result.stderr.length > 0) {
          status.text = "Ruby LSP: Update failed";
          status.command = {
            title: "Try again",
            command: commandId,
          };

          if (
            result.stderr.includes(
              "Bundler attempted to update ruby-lsp but its version stayed the same"
            )
          ) {
            vscode.window.showWarningMessage(
              "Could not update the ruby-lsp gem. Is the version in the Gemfile pinned?"
            );
          } else {
            vscode.window.showErrorMessage("Failed to update gem.");
          }
        } else {
          status.dispose();
        }
      })
    );

    status.command = {
      title: "Update",
      command: commandId,
    };
  }

  private createYjitStatus(ruby: Ruby) {
    const useYjit = vscode.workspace.getConfiguration("rubyLsp").get("yjit");

    let [major, minor]: number[] = [0, 0];

    if (this.ruby.rubyVersion) {
      [major, minor] = this.ruby.rubyVersion.split(".").map(Number);
    }

    const yjit: vscode.LanguageStatusItem =
      vscode.languages.createLanguageStatusItem("yjit", this.selector);
    yjit.name = "Ruby LSP Status";

    if (useYjit && ruby.yjitEnabled && [major, minor] >= [3, 2]) {
      yjit.text = "Ruby LSP: YJIT is in use";
    } else {
      yjit.text = "Ruby LSP: YJIT is not in use";
      if ([major, minor] >= [3, 2]) {
        yjit.severity = vscode.LanguageStatusSeverity?.Warning;
        yjit.command = {
          title: "Enable it",
          command: "",
        };
      } else {
        yjit.severity = vscode.LanguageStatusSeverity?.Information;
      }
    }
  }

  private createRubyStatus(ruby: Ruby) {
    const rubyVersion: vscode.LanguageStatusItem =
      vscode.languages.createLanguageStatusItem("rubyVersion", this.selector);
    rubyVersion.name = "Ruby LSP Status";
    rubyVersion.text = `Using Ruby ${ruby.rubyVersion}`;
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
}
