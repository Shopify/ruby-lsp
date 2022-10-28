import * as vscode from "vscode";

import Client from "./client";
import { Telemetry } from "./telemetry";
import { Ruby } from "./ruby";
import { isGemOutdated, updateGem } from "./bundler";

let client: Client;

export async function activate(context: vscode.ExtensionContext) {
  const ruby = new Ruby();
  await ruby.activateRuby();

  const telemetry = new Telemetry(context);
  client = new Client(context, telemetry, ruby);

  // Adding this delay guarantees that the Ruby environment is activated before trying to start the server
  await client.start();

  activateGemOutdatedButton(context);
}

export async function deactivate(): Promise<void> {
  if (client) {
    return client.stop();
  }
}

async function activateGemOutdatedButton(context: vscode.ExtensionContext) {
  const gemOutdated = await isGemOutdated();
  if (!gemOutdated) {
    return;
  }

  const commandId = "updateOutdatedGem";

  const gemOutdatedButton = vscode.window.createStatusBarItem(
    vscode.StatusBarAlignment.Left,
    0
  );

  gemOutdatedButton.text = "$(plug) Update Ruby LSP";
  gemOutdatedButton.tooltip =
    "The ruby-lsp gem is not up-to-date. Press this button to install the latest version of the gem.";
  gemOutdatedButton.command = commandId;

  context.subscriptions.push(
    vscode.commands.registerCommand(commandId, async () => {
      gemOutdatedButton.text = "$(loading~spin) Updating Ruby LSP";
      const result = await updateGem();

      if (result.stderr.length > 0) {
        gemOutdatedButton.text = "$(close) Ruby LSP Update Failed";

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
        vscode.window.showInformationMessage("Successfully updated Ruby LSP.");
        gemOutdatedButton.hide();
      }
    })
  );

  gemOutdatedButton.show();
}
