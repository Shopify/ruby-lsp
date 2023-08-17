import * as vscode from "vscode";

import Client from "./client";
import { Telemetry } from "./telemetry";
import { Ruby } from "./ruby";
import { Debugger } from "./debugger";
import { TestController } from "./testController";
import DocumentProvider from "./documentProvider";

let client: Client | undefined;
let debug: Debugger | undefined;
let testController: TestController | undefined;

export async function activate(context: vscode.ExtensionContext) {
  const ruby = new Ruby(context);
  await ruby.activateRuby();

  const telemetry = new Telemetry(context);
  await telemetry.sendConfigurationEvents();

  testController = new TestController(
    context,
    vscode.workspace.workspaceFolders![0].uri.fsPath,
    ruby,
    telemetry,
  );

  client = new Client(context, telemetry, ruby, testController);

  await client.start();
  debug = new Debugger(context, ruby);

  vscode.workspace.registerTextDocumentContentProvider(
    "ruby-lsp",
    new DocumentProvider(),
  );
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
