import * as vscode from "vscode";

import Client from "./client";
import { Telemetry } from "./telemetry";
import { Ruby } from "./ruby";

let client: Client;

export async function activate(context: vscode.ExtensionContext) {
  await new Ruby().activateRuby();

  const telemetry = new Telemetry(context);
  client = new Client(context, telemetry);

  // Adding this delay guarantees that the Ruby environment is activated before trying to start the server
  await delay(500);
  await client.start();
}

async function delay(mseconds: number) {
  return new Promise((resolve) => {
    setTimeout(resolve, mseconds);
  });
}

export async function deactivate(): Promise<void> {
  if (client) {
    return client.stop();
  }
}
