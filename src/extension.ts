import * as vscode from "vscode";

import Client from "./client";
import { Telemetry } from "./telemetry";
import { Ruby } from "./ruby";

let client: Client;

export async function activate(context: vscode.ExtensionContext) {
  const ruby = new Ruby();
  await ruby.activateRuby();

  const telemetry = new Telemetry(context);
  client = new Client(context, telemetry, ruby);

  await client.start();
}

export async function deactivate(): Promise<void> {
  if (client) {
    return client.stop();
  }
}
