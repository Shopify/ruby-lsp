import * as vscode from "vscode";

import Client from "./client";
import { Telemetry } from "./telemetry";
import { Ruby } from "./ruby";
import { Debugger } from "./debugger";
import { TestController } from "./testController";

let client: Client;
let debug: Debugger;
let testController: TestController;

export async function activate(context: vscode.ExtensionContext) {
  const ruby = new Ruby(context);
  await ruby.activateRuby();

  const telemetry = new Telemetry(context);
  testController = new TestController(
    context,
    vscode.workspace.workspaceFolders![0].uri.fsPath,
    ruby
  );

  client = new Client(context, telemetry, ruby, testController);

  await client.start();
  debug = new Debugger(context, ruby);
}

export async function deactivate(): Promise<void> {
  if (client) {
    await client.stop();
  }

  if (testController) {
    testController.dispose();
  }

  if (debug) {
    debug.dispose();
  }
}
