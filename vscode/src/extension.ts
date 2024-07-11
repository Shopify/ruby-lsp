import os from "os";

import * as vscode from "vscode";

import { RubyLsp } from "./rubyLsp";
import { LOG_CHANNEL } from "./common";

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

  const logger = await createLogger(context);
  context.subscriptions.push(logger);

  extension = new RubyLsp(context, logger);
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

async function createLogger(context: vscode.ExtensionContext) {
  let sender;

  switch (context.extensionMode) {
    case vscode.ExtensionMode.Development:
      sender = {
        sendEventData: (eventName: string, data?: Record<string, any>) => {
          LOG_CHANNEL.debug(eventName, data);
        },
        sendErrorData: (error: Error, data?: Record<string, any>) => {
          LOG_CHANNEL.error(error, data);
        },
      };
      break;
    case vscode.ExtensionMode.Test:
      sender = {
        sendEventData: (_eventName: string, _data?: Record<string, any>) => {},
        sendErrorData: (_error: Error, _data?: Record<string, any>) => {},
      };
      break;
    default:
      try {
        let counter = 0;

        // If the extension that implements the getTelemetrySenderObject is not activated yet, the first invocation to
        // the command will activate it, but it might actually return `null` rather than the sender object. Here we try
        // a few times to receive a non `null` object back because we know that the getTelemetrySenderObject command
        // exists (otherwise, we end up in the catch clause)
        while (!sender && counter < 5) {
          await vscode.commands.executeCommand("getTelemetrySenderObject");

          sender =
            await vscode.commands.executeCommand<vscode.TelemetrySender | null>(
              "getTelemetrySenderObject",
            );

          counter++;
        }
      } catch (error: any) {
        sender = {
          sendEventData: (
            _eventName: string,
            _data?: Record<string, any>,
          ) => {},
          sendErrorData: (_error: Error, _data?: Record<string, any>) => {},
        };
      }
      break;
  }

  if (!sender) {
    sender = {
      sendEventData: (_eventName: string, _data?: Record<string, any>) => {},
      sendErrorData: (_error: Error, _data?: Record<string, any>) => {},
    };
  }

  return vscode.env.createTelemetryLogger(sender, {
    ignoreBuiltInCommonProperties: true,
    ignoreUnhandledErrors:
      context.extensionMode === vscode.ExtensionMode.Test ||
      context.extensionMode === vscode.ExtensionMode.Development,
    additionalCommonProperties: {
      extensionVersion: context.extension.packageJSON.version,
      environment: os.platform(),
    },
  });
}
