import * as vscode from "vscode";

import { RubyLsp } from "./rubyLsp";

let extension: RubyLsp;

export async function activate(context: vscode.ExtensionContext) {
  await migrateManagerConfigurations();

  if (!vscode.workspace.workspaceFolders) {
    // We currently don't support usage without any workspace folders opened. Here we warn the user, point to the issue
    // and offer to open a folder instead
    const answer = await vscode.window.showWarningMessage(
      `Using the Ruby LSP without any workspaces opened is currently not supported
      ([learn more](https://github.com/Shopify/ruby-lsp/issues/1780))`,
      "Open a workspace",
      "Continue anyway",
    );

    if (answer === "Open a workspace") {
      await vscode.commands.executeCommand("workbench.action.files.openFolder");
    }

    return;
  }

  extension = new RubyLsp(context);
  await extension.activate();
}

export async function deactivate(): Promise<void> {
  await extension.deactivate();
}

type InspectKeys =
  | "globalValue"
  | "workspaceValue"
  | "workspaceFolderValue"
  | "globalLanguageValue"
  | "workspaceLanguageValue"
  | "workspaceFolderLanguageValue";
// Function to migrate the old version manager configuration to the new format. Remove this after a few months
async function migrateManagerConfigurations() {
  const configuration = vscode.workspace.getConfiguration("rubyLsp");
  const currentManagerSettings =
    configuration.inspect<string>("rubyVersionManager")!;
  let identifier: string | undefined;

  const targetMap: Record<InspectKeys, vscode.ConfigurationTarget> = {
    globalValue: vscode.ConfigurationTarget.Global,
    globalLanguageValue: vscode.ConfigurationTarget.Global,
    workspaceFolderLanguageValue: vscode.ConfigurationTarget.WorkspaceFolder,
    workspaceFolderValue: vscode.ConfigurationTarget.WorkspaceFolder,
    workspaceLanguageValue: vscode.ConfigurationTarget.Workspace,
    workspaceValue: vscode.ConfigurationTarget.Workspace,
  };

  for (const [key, target] of Object.entries(targetMap)) {
    identifier = currentManagerSettings[key as InspectKeys];

    if (identifier && typeof identifier === "string") {
      await configuration.update("rubyVersionManager", { identifier }, target);
    }
  }
}
