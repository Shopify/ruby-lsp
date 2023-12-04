import * as vscode from "vscode";

import { RubyLsp } from "./rubyLsp";

let extension: RubyLsp;

export async function activate(context: vscode.ExtensionContext) {
  if (!vscode.workspace.workspaceFolders) {
    return;
  }

  extension = new RubyLsp(context);
  await extension.activate();
}

export async function deactivate(): Promise<void> {
  await extension.deactivate();
}
