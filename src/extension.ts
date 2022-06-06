import * as vscode from "vscode";

import Client from "./client";
import { Telemetry } from "./telemetry";

let client: Client;

export async function activate(context: vscode.ExtensionContext) {
  activateRuby();

  const telemetry = new Telemetry(context);
  client = new Client(context, telemetry);

  // Adding this delay guarantees that shadowenv has enough time to load the right environment
  await delay(500);
  await client.start();
}

async function delay(mseconds: number) {
  return new Promise((resolve) => {
    setTimeout(resolve, mseconds);
  });
}

function activateRuby() {
  vscode.extensions.getExtension("shopify.vscode-shadowenv")?.activate();
}

export async function deactivate() {
  if (client) {
    await client.stop();
  }
}
