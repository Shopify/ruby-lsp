import * as vscode from "vscode";

import Client from "./client";
import { Telemetry } from "./telemetry";
import { Ruby } from "./ruby";
import { Debugger } from "./debugger";

let client: Client;
let debug: Debugger;

export async function activate(context: vscode.ExtensionContext) {
  const ruby = new Ruby(context);
  await ruby.activateRuby();

  const telemetry = new Telemetry(context);
  client = new Client(context, telemetry, ruby);

  await client.start();
  debug = new Debugger(context, ruby);
}

export async function deactivate(): Promise<void> {
  if (client) {
    await client.stop();
<<<<<<< HEAD
=======
    client.dispose();
>>>>>>> 2499083 (Add test controller)
  }

  if (debug) {
    debug.dispose();
  }
}
