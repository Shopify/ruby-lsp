import * as vscode from "vscode";

import Client from "./client";

let client: Client;

export async function activate(context: vscode.ExtensionContext) {
  activateRuby();

  client = new Client(context);
  await client.start();
}

function activateRuby() {
  vscode.extensions.getExtension("shopify.vscode-shadowenv")?.activate();
}

export async function deactivate() {
  if (client) {
    await client.stop();
  }
}
