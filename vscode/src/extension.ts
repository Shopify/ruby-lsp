import * as vscode from "vscode";

import { RubyLsp } from "./rubyLsp";

let extension: RubyLsp;

export async function activate(context: vscode.ExtensionContext) {
  if (!vscode.workspace.workspaceFolders) {
    return;
  }

  extension = new RubyLsp(context);
  await extension.activate();

  await migrateManagerConfigurations();
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
