import * as vscode from "vscode";

import * as Bundler from "./bundler";
import { Ruby } from "./ruby";

export enum ServerCommand {
  Start = "ruby-lsp.start",
  Stop = "ruby-lsp.stop",
  Restart = "ruby-lsp.restart",
}

export class StatusItem {
  private context: vscode.ExtensionContext;
  private ruby: Ruby;
  private selector: vscode.DocumentSelector;
  private serverStatus: vscode.LanguageStatusItem;
  private yjitStatus: vscode.LanguageStatusItem;

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
      vscode.LanguageStatusSeverity?.Information
    );

    this.serverStatus.command = {
      title: "Restart server",
      command: "rubyLsp.serverOptions",
    };

    this.yjitStatus = vscode.languages.createLanguageStatusItem(
      "yjit",
      this.selector
    );

    this.createYjitStatus(this.ruby);
    this.createRubyStatus(this.ruby);

    this.registerCommands();
  }

  public async updateStatus(status: ServerCommand) {
    this.serverStatus.severity = vscode.LanguageStatusSeverity?.Information;

    switch (status) {
      case ServerCommand.Start: {
        this.serverStatus.text = "Ruby LSP: Running...";
        this.serverStatus.command!.title = "Stop Server";

        this.activateGemOutdatedButton();

        break;
      }
      case ServerCommand.Stop: {
        this.serverStatus.text = "Ruby LSP: Stopped";
        this.serverStatus.command!.title = "Start Server";

        break;
      }
      case ServerCommand.Restart: {
        this.serverStatus.text = "Ruby LSP: Error";
        this.serverStatus.severity = vscode.LanguageStatusSeverity?.Error;
        this.serverStatus.command!.title = "Restart Server";
      }
    }
  }

  public async installGems(): Promise<boolean> {
    if (!(await Bundler.bundleCheck())) {
      this.serverStatus.text = "Ruby LSP: Error";
      this.serverStatus.severity = vscode.LanguageStatusSeverity?.Error;

      const status: vscode.LanguageStatusItem = this.createStatusItem(
        "installGems",
        "Ruby LSP: The gems in the bundle are not installed.",
        vscode.LanguageStatusSeverity?.Error
      );

      const commandId = "rubyLsp.installGems";

      this.context.subscriptions.push(
        vscode.commands.registerCommand(commandId, () => {
          status.text = "Ruby LSP: Installing gems...";
          status.busy = true;
          Bundler.bundleInstall()
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
        command: commandId,
      };
      return true;
    }
    return false;
  }

  public async addMissingGem(): Promise<boolean> {
    if (await Bundler.isGemMissing()) {
      this.serverStatus.text = "Ruby LSP: Error";
      this.serverStatus.severity = vscode.LanguageStatusSeverity?.Error;

      const status: vscode.LanguageStatusItem = this.createStatusItem(
        "addMissingGem",
        "Ruby LSP: Bundle Add",
        vscode.LanguageStatusSeverity?.Error
      );

      const commandId = "rubyLsp.addMissingGem";

      this.context.subscriptions.push(
        vscode.commands.registerCommand(commandId, () => {
          status.text = "Ruby LSP: Adding gem...";
          status.busy = true;
          Bundler.addGem()
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
    const gemOutdated = await Bundler.isGemOutdated();
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
        status.text = "Ruby LSP: Updating Ruby LSP...";
        status.busy = true;

        const result = await Bundler.updateGem();

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

    this.yjitStatus.name = "Ruby LSP Status";

    if (useYjit && ruby.yjitEnabled && [major, minor] >= [3, 2]) {
      this.yjitStatus.text = "YJIT enabled";

      this.yjitStatus.command = {
        title: "Disable",
        command: "rubyLsp.toggleYjit",
      };
    } else {
      this.yjitStatus.text = "YJIT disabled";
      if ([major, minor] >= [3, 2] && ruby.yjitEnabled) {
        this.yjitStatus.command = {
          title: "Enable",
          command: "rubyLsp.toggleYjit",
        };
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

  private registerCommands() {
    this.context.subscriptions.push(
      vscode.commands.registerCommand("rubyLsp.toggleYjit", async () => {
        const lspConfig = vscode.workspace.getConfiguration("rubyLsp");
        const yjitEnabled = lspConfig.get("yjit");
        lspConfig.update("yjit", !yjitEnabled);
        this.yjitStatus.text = yjitEnabled ? "YJIT disabled" : "YJIT enabled";
        this.yjitStatus.command!.title = yjitEnabled ? "Enable" : "Disable";
      })
    );

    this.context.subscriptions.push(
      vscode.commands.registerCommand("rubyLsp.serverOptions", async () => {
        const result = await vscode.window.showQuickPick(
          [
            { label: "Ruby LSP: Start", description: "ruby-lsp.start" },
            { label: "Ruby LSP: Stop", description: "ruby-lsp.stop" },
            { label: "Ruby LSP: Restart", description: "ruby-lsp.restart" },
          ],
          {
            placeHolder: "Select server action",
          }
        );

        if (result !== undefined)
          await vscode.commands.executeCommand(result.description);
      })
    );
  }
}
